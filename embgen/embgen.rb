#!/usr/bin/env ruby
# embgen.rb
# Ruby port of embgen.tcl: processes embedded generator blocks inside files,
# evaluates generator macros, and refreshes generated regions in place.

require 'json'
require 'optparse'
require 'pathname'
require 'open3'
require 'fileutils'
require 'rexml/document'
require 'rexml/xpath'

module Embgen
  INSTALL_DIR = File.expand_path(File.dirname(__FILE__)).freeze

  def self.add_to_status(msg)
    return if msg.nil? || msg.strip.empty?
    warn("embgen: #{msg}")
  end

  # -----------------------------
  # Helper/DSL utilities
  # -----------------------------
  module Helpers
    def emit(str)
      @macro_buffer << str.to_s
    end

    def emitted
      @macro_buffer
    end

    def emit_to_file(path, content)
      @context.queue_file_output(path, content)
    end

    def emit_file(path, &block)
      raise ArgumentError, 'emit_file requires a block' unless block
      saved = @macro_buffer
      @macro_buffer = +''
      instance_eval(&block)
      @context.queue_file_output(path, @macro_buffer)
    ensure
      @macro_buffer = saved
    end

    def upper_case(str) = str.to_s.upcase
    def lower_case(str) = str.to_s.downcase

    def camel_case(str)
      tokens = str.to_s.gsub(/[_\-]+/, ' ').split(/\s+/)
      return '' if tokens.empty?
      [tokens.first.downcase, *tokens.drop(1).map { |t| t.capitalize }].join
    end

    def pascal_case(str)
      str.to_s.gsub(/(?:^|[_\-]+\s*)(\w)/) { Regexp.last_match(1).upcase }
    end

    def snake_case(str)
      str.to_s
         .gsub(/([A-Z]+)/) { "_#{Regexp.last_match(1)}" }
         .gsub(/[\- ]+/, '_')
         .sub(/\A_/, '')
         .downcase
    end

    def kebab_case(str)
      snake_case(str).tr('_', '-')
    end

    def comma_separate(list, lparen = '', rparen = '')
      list.map { |item| "#{lparen}#{item}#{rparen}" }.join(',')
    end

    def permutations(list, prefix = [])
      return [prefix] if list.empty?
      list.each_with_index.flat_map do |item, idx|
        remaining = list.dup
        remaining.delete_at(idx)
        permutations(remaining, prefix + [item])
      end
    end

    def combinations(list, size)
      return [[]] if size.zero?
      return [] if list.empty?
      head, *tail = list
      with_head = combinations(tail, size - 1).map { |c| [head, *c] }
      without_head = combinations(tail, size)
      with_head + without_head
    end

    def seq(from, to)
      step = from <= to ? 1 : -1
      (from..to).step(step).to_a
    end

    def suffixes(list)
      (0...list.length).map { |idx| list[idx..] }
    end

    def prefixes(list)
      (0...list.length).map { |idx| list[0..idx] }
    end
  end

  # -----------------------------
  # Internal runtime for macro eval
  # -----------------------------
  class Runtime
    include Helpers
    attr_reader :context

    def initialize(context)
      @context = context
      @macro_buffer = +''
      @binding = binding
    end

    def reset_buffer
      @macro_buffer = +''
    end

    def buffer_content
      @macro_buffer
    end

    def with_variables(vars)
      vars.each { |k, v| @binding.local_variable_set(k.to_sym, v) }
      yield
    end

    def eval_code(code, file_label = '<embedded>')
      eval(code, @binding, file_label, 1)
    rescue StandardError => e
      Embgen.add_to_status("#{file_label}: #{e.class}: #{e.message}")
    end
  end

  # -----------------------------
  # Engine: orchestrates generators + file processing
  # -----------------------------
  class Engine
    attr_reader :generators, :current_comment_prefix

    def initialize(status_io: $stderr, runner: nil)
      @status_io = status_io
      @runner = runner || method(:default_run_command)
      @generators = {}
      @pending_file_outputs = {}
      @current_file = nil
      @current_comment_prefix = ''
    end

    def register_builtin_generators
      add_generator('echo', method(:gen_echo))
      add_generator('dot', method(:gen_dot))
      add_generator('plantuml', method(:gen_plantuml))
      add_generator('plantuml_ascii', method(:gen_plantuml_ascii))
      add_generator('xml_driven_macro', method(:gen_xml_driven_macro))
      add_generator('json_driven_macro', method(:gen_json_driven_macro))
      add_generator('ruby_macro', method(:gen_ruby_macro))
      add_generator('latex', method(:gen_latex))
      add_generator('latex_inline', ->(note, uuid, fname, _rt) { gen_latex(note, uuid, fname, inline: true) })
      add_generator('using_command_line', method(:gen_using_command_line))
    end

    def add_generator(type, callable)
      @generators[type] = callable
    end

    def process_file(filename)
      unless File.file?(filename)
        Embgen.add_to_status("File not found: #{filename}")
        return
      end

      # Fast skip for binaries / files without embgen markers
      raw = File.binread(filename)
      unless raw.include?('embgen_embedded_generator') || raw.include?('g4_embedded_generator')
        return
      end

      content = File.read(filename, encoding: 'UTF-8', invalid: :replace, undef: :replace).gsub(/\r\n?/, "\n")
      lines = content.split("\n", -1) # keep trailing empty line
      out_lines = []

      in_header = false
      in_generated = false
      current_gen_type = nil
      current_uuid = nil
      note_lines = []
      current_indent = ''
      @current_comment_prefix = ''

      lines.each do |line|
        normalized = line.gsub(/g4_/, 'embgen_')
        if !in_header && !in_generated
          if normalized =~ /^\s*(\/+|#+|--+|;+|%+)\s*embgen_embedded_generator\s+(\S+)\s+(\S+)/
            in_header = true
            current_gen_type = Regexp.last_match(2)
            current_uuid = Regexp.last_match(3)
            note_lines = []
            current_indent = ''
            @current_comment_prefix = Regexp.last_match(1)
            out_lines << line
            next
          end
          out_lines << line
          next
        end

        if in_header && !in_generated
          if normalized =~ /^\s*(\/+|#+|--+|;+|%+)\s*embgen_generated_start\s+(\S+)/
            found_uuid = Regexp.last_match(2)
            warn_uuid_mismatch(filename, current_uuid, found_uuid, 'start') if found_uuid != current_uuid
            in_generated = true
            current_indent = line[/^(\s*)/, 1] || ''
            out_lines << line
            next
          end

          if line =~ /^\s*(\/+|#+|--+|;+|%+)\s?(.*)$/
            note_lines << Regexp.last_match(2)
          else
            note_lines << line
          end
          out_lines << line
          next
        end

        if in_generated
          if normalized =~ /^\s*(\/\/+|#+|--+|;+|%+|\/+)\s*embgen_generated_end\s+(\S+)/
            found_uuid = Regexp.last_match(2)
            warn_uuid_mismatch(filename, current_uuid, found_uuid, 'end') if found_uuid != current_uuid

            note_text = note_lines.join("\n")
            @current_file = filename
            generated = run_generator(current_gen_type, note_text, current_uuid, filename)
            unless generated.nil? || generated.empty?
              generated.split("\n", -1).each do |gen_line|
                out_lines << (gen_line.empty? ? '' : "#{current_indent}#{gen_line}")
              end
            end
            out_lines << line

            in_generated = false
            in_header = false
            current_gen_type = nil
            current_uuid = nil
            note_lines = []
            current_indent = ''
            next
          end
          # skip previous generated body
          next
        end
      end

      File.write(filename, out_lines.join("\n"), mode: 'w', encoding: 'UTF-8')
    end

    def run_generator(type, note_text, uuid, filename)
      unless @generators.key?(type)
        Embgen.add_to_status("No generator registered for type '#{type}' in #{filename} (uuid #{uuid})")
        return ''
      end
      @pending_file_outputs.clear
      runtime = Runtime.new(self)
      runtime.instance_variable_set(:@macro_buffer, +'')
      runtime.instance_variable_set(:@context, self)
      @generators[type].call(note_text, uuid, filename, runtime).tap do
        flush_pending_files
      end
    end

    # -----------------------------
    # Generator implementations
    # -----------------------------
    def gen_echo(note_text, _uuid, _filename, _runtime)
      note_text
    end

    def gen_using_command_line(note_text, _uuid, filename, _runtime)
      cmdline = note_text.strip
      return comment_line('using_command_line: empty command') if cmdline.empty?
      stdout, stderr, status = @runner.call(cmdline)
      unless status.success?
        Embgen.add_to_status("Command failed in #{filename}: #{cmdline} : #{stderr.strip}")
        return comment_line("CMD ERROR: #{stderr.strip}")
      end
      stdout
    end

    def gen_dot(note_text, uuid, filename, _runtime)
      dir = File.dirname(filename)
      base = File.basename(filename, File.extname(filename))
      dot_file = File.join(dir, "#{base}.#{uuid}.dot")
      png_file = File.join(dir, "#{base}.#{uuid}.png")

      File.write(dot_file, note_text, encoding: 'UTF-8')
      stdout, stderr, status = @runner.call(%(dot -Tpng "#{dot_file}" -o "#{png_file}"))
      unless status.success?
        Embgen.add_to_status("dot error (#{dot_file}): #{stderr.strip}")
        return comment_line("dot generation failed: #{stderr.strip}")
      end
      Embgen.add_to_status("dot -Tpng #{dot_file} -o #{png_file}")
      File.delete(dot_file) rescue nil
      comment_line("DOT graph generated at: #{png_file}")
    end

    def gen_plantuml(note_text, uuid, filename, _runtime)
      dir = File.dirname(filename)
      base = File.basename(filename, File.extname(filename))
      pu_file = File.join(dir, "#{base}.#{uuid}.puml")

      File.write(pu_file, note_text, encoding: 'UTF-8')
      cmd = %(java -jar "#{File.join(INSTALL_DIR, 'plantuml', 'plantuml.jar')}" -tpng "#{pu_file}")
      _stdout, stderr, status = @runner.call(cmd)
      unless status.success?
        Embgen.add_to_status("plantuml error (#{pu_file}): #{stderr.strip}")
        return comment_line("plantuml generation failed: #{stderr.strip}")
      end

      png_file = "#{File.join(dir, "#{base}.#{uuid}")}.png"
      unless File.exist?(png_file)
        candidates = Dir.glob(File.join(dir, "#{base}.#{uuid}*.png"))
        png_file = candidates.first if candidates.any?
      end
      Embgen.add_to_status("plantuml -tpng #{pu_file}")
      File.delete(pu_file) rescue nil
      comment_line("PlantUML image generated at: #{png_file}")
    end

    def gen_plantuml_ascii(note_text, uuid, filename, _runtime)
      dir = File.dirname(filename)
      base = File.basename(filename, File.extname(filename))
      pu_file = File.join(dir, "#{base}.#{uuid}.puml")

      File.write(pu_file, note_text, encoding: 'UTF-8')
      cmd = %(java -jar "#{File.join(INSTALL_DIR, 'plantuml', 'plantuml.jar')}" -ttxt "#{pu_file}")
      _stdout, stderr, status = @runner.call(cmd)
      unless status.success?
        Embgen.add_to_status("plantuml -ttxt error (#{pu_file}): #{stderr.strip}")
        return comment_line("plantuml ascii generation failed: #{stderr.strip}")
      end

      outfiles = Dir.glob(File.join(dir, "#{base}.#{uuid}*.atxt")).sort.reverse
      generated = outfiles.map { |f| File.read(f, encoding: 'UTF-8') }.join("\n")
      outfiles.each { |f| File.delete(f) rescue nil }
      File.delete(pu_file) rescue nil
      return comment_line("No ASCII PlantUML output found for #{pu_file}") if generated.empty?
      generated
    end

    def gen_latex(note_text, uuid, filename, _runtime = nil, inline: false)
      dir = File.dirname(filename)
      base = File.basename(filename, File.extname(filename))

      latex_preamble = <<~TEX
        \\documentclass{article}
        \\usepackage[utf8]{inputenc}
        \\usepackage{mathtools}
        \\pagestyle{empty}
      TEX
      body = <<~TEX
        \\begin{document}
        %s
        \\end{document}
      TEX
      formatted_body = format(body, note_text)

      tex_file = File.join(dir, "#{base}.#{uuid}.temp.tex")
      File.write(tex_file, latex_preamble + formatted_body, encoding: 'UTF-8')

      latex_cmd = %(latex -output-directory "#{dir}" "#{tex_file}")
      _out, stderr, status = @runner.call(latex_cmd)
      unless status.success?
        Embgen.add_to_status("latex error (#{tex_file}): #{stderr.strip}")
        return comment_line("LaTeX compile failed: #{stderr.strip}")
      end

      dvi_file = File.join(dir, "#{base}.#{uuid}.temp.dvi")
      png_file = File.join(dir, "#{base}.#{uuid}.png")
      _out, stderr, status = @runner.call(%(dvipng -T tight -o "#{png_file}" "#{dvi_file}"))
      unless status.success?
        Embgen.add_to_status("dvipng error (#{dvi_file}): #{stderr.strip}")
        return comment_line("dvipng failed: #{stderr.strip}")
      end

      [tex_file, dvi_file,
       File.join(dir, "#{base}.#{uuid}.temp.aux"),
       File.join(dir, "#{base}.#{uuid}.temp.log")].each { |f| File.delete(f) rescue nil }
      inline ? comment_line("LaTeX inline PNG: #{png_file}") : comment_line("LaTeX PNG generated at: #{png_file}")
    end

    def gen_ruby_macro(note_text, _uuid, filename, runtime)
      runtime.reset_buffer
      runtime.eval_code(note_text, filename)
      runtime.buffer_content
    end

    def gen_xml_driven_macro(note_text, _uuid, filename, runtime)
      directives = parse_directives(note_text)
      generated = +''
      directives.each do |fname, xpath, code_body|
        runtime.reset_buffer
        if fname.nil? || fname.empty? || fname == '{}'
          runtime.eval_code(code_body, filename)
          generated << runtime.buffer_content
          next
        end
        resolved = resolve_embgen_path(filename, fname)
        unless resolved && File.file?(resolved)
          Embgen.add_to_status("XML file not found: #{fname}")
          next
        end
        xml = File.read(resolved, encoding: 'UTF-8', invalid: :replace, undef: :replace)
        doc = REXML::Document.new(xml)
        REXML::XPath.match(doc, xpath).each do |node|
          vars = node.attributes.to_h.transform_keys(&:to_s)
          vars['xpathnode'] = node
          runtime.with_variables(vars) { runtime.eval_code(code_body, resolved) }
        end
        generated << runtime.buffer_content
      end
      generated
    end

    def gen_json_driven_macro(note_text, _uuid, filename, runtime)
      directives = parse_directives(note_text)
      generated = +''
      directives.each do |fname, path_spec_raw, code_body|
        runtime.reset_buffer
        if fname.nil? || fname.empty? || fname == '{}'
          runtime.eval_code(code_body, filename)
          generated << runtime.buffer_content
          next
        end
        resolved = resolve_embgen_path(filename, fname)
        unless resolved && File.file?(resolved)
          Embgen.add_to_status("JSON file not found: #{fname}")
          next
        end
        data = JSON.parse(File.read(resolved, encoding: 'UTF-8'))
        targets = evaluate_json_path(data, parse_tcl_list(path_spec_raw))
        Array(targets).each do |source|
          if source.is_a?(Hash)
            runtime.with_variables(source) { runtime.eval_code(code_body, resolved) }
          else
            runtime.with_variables('item' => source) { runtime.eval_code(code_body, resolved) }
          end
        end
        generated << runtime.buffer_content
      end
      generated
    end

    # -----------------------------
    # Path + file helpers
    # -----------------------------
    def normalize_output_path(path)
      pn = Pathname.new(path)
      if pn.absolute?
        return pn.exist? ? pn.realpath.to_s : pn.to_s
      end
      base_dir = @current_file ? File.dirname(@current_file) : Dir.pwd
      File.expand_path(path, base_dir)
    end

    def queue_file_output(path, content)
      normalized = normalize_output_path(path)
      @pending_file_outputs[normalized] ||= +''
      @pending_file_outputs[normalized] << content
    end

    def flush_pending_files
      @pending_file_outputs.each do |path, content|
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        File.write(path, content, encoding: 'UTF-8')
        Embgen.add_to_status("wrote generated file: #{path}")
      rescue StandardError => e
        Embgen.add_to_status("could not write #{path}: #{e.message}")
      end
      @pending_file_outputs.clear
    end

    def comment_line(text)
      prefix = @current_comment_prefix.nil? || @current_comment_prefix.empty? ? '#' : @current_comment_prefix
      "#{prefix} #{text}"
    end

    def resolve_embgen_path(current_file, ref_path)
      pn = Pathname.new(ref_path)
      return pn.to_s if pn.absolute?

      search_dir = Pathname.new(current_file).dirname
      loop do
        candidate = search_dir.join(ref_path)
        return candidate.to_s if candidate.exist?
        parent = search_dir.parent
        break if parent == search_dir
        search_dir = parent
      end
      ''
    end

    def should_include?(path, include_pats, exclude_pats)
      npath = File.expand_path(path).tr('\\', '/')
      ok = include_pats.any? { |pat| File.fnmatch?(pat, npath) }
      return false unless ok
      exclude_pats.none? { |pat| File.fnmatch?(pat, npath) }
    end

    def collect_files(dir, include_pats, exclude_pats, result)
      Dir.children(dir).each do |entry|
        full = File.join(dir, entry)
        if File.directory?(full)
          collect_files(full, include_pats, exclude_pats, result)
        elsif File.file?(full)
          result << File.expand_path(full) if should_include?(full, include_pats, exclude_pats)
        end
      end
    end

    def read_list_file(list_file)
      paths = []
      unless File.file?(list_file)
        Embgen.add_to_status("list file not found: #{list_file}")
        return paths
      end
      list_dir = File.dirname(File.expand_path(list_file))
      File.read(list_file, encoding: 'UTF-8').split("\n").each do |raw|
        p = raw.strip
        next if p.empty?
        candidates = if Pathname.new(p).absolute?
                       [p]
                     else
                       [File.expand_path(p), File.expand_path(p, list_dir)]
                     end
        resolved = candidates.find { |c| File.file?(c) }
        if resolved
          paths << resolved
        else
          Embgen.add_to_status("list entry not found: #{p}")
        end
      end
      paths
    end

    # -----------------------------
    # JSON path evaluation helpers
    # -----------------------------
    def parse_tcl_list(str)
      stack = [[]]
      token = +''
      str.each_char do |ch|
        case ch
        when '{'
          stack.last << token unless token.empty?
          token = +''
          stack << []
        when '}'
          stack.last << token unless token.empty?
          token = +''
          finished = stack.pop
          stack.last << finished
        when ' ', "\t", "\n", "\r"
          next if token.empty?
          stack.last << token
          token = +''
        else
          token << ch
        end
      end
      stack.last << token unless token.empty?
      stack.first
    end

    def evaluate_predicate(pathelem, target)
      if pathelem.first == 'AND'
        pathelem.drop(1).all? { |sub| evaluate_predicate(Array(sub), target) }
      elsif pathelem.first == 'OR'
        pathelem.drop(1).any? { |sub| evaluate_predicate(Array(sub), target) }
      elsif pathelem.first == 'NOT'
        pathelem.drop(1).none? { |sub| evaluate_predicate(Array(sub), target) }
      else
        return false unless target.respond_to?(:[])
        key, op, value = if pathelem.length == 2
                           [pathelem[0], 'EQUALS', pathelem[1]]
                         else
                           pathelem
                         end
        data_value = target[key] || target[key.to_s] || target[key.to_sym]
        case op
        when 'EQUALS' then data_value.to_s == value.to_s
        when 'MATCHES' then !!(data_value.to_s =~ /#{value}/)
        else false
        end
      end
    end

    def evaluate_json_path(data, path_spec)
      target = data
      Array(path_spec).each do |elem|
        if elem.is_a?(Array) && elem.length > 1
          found = Array(target).find { |x| evaluate_predicate(elem, x) }
          return [] unless found
          target = found
        elsif elem.is_a?(String) && elem.start_with?('[') && elem.end_with?(']')
          idx = elem[1..-2].to_i
          target = Array(target)[idx]
        else
          key = elem.is_a?(Array) ? elem.first : elem
          target = case target
                   when Hash then target[key] || target[key.to_s] || target[key.to_sym]
                   when Array then target.map { |item| item[key] || item[key.to_s] || item[key.to_sym] }
                   else nil
                   end
        end
      end
      target.is_a?(Array) ? target : [target]
    end

    # -----------------------------
    # Directive parsing
    # -----------------------------
    def parse_directives(note_text)
      script = note_text.gsub(/^\s*@/, "\u0001").gsub(/[\r\n]\s*@/, "\u0001")
      script.split("\u0001").filter_map do |raw|
        line = raw.strip
        next if line.empty?
        fname, rest = line.split(/\s+/, 2)
        next unless fname && rest
        fname = fname.gsub(/\A["']|["']\z/, '')
        path_block, remaining = extract_braced(rest.strip)
        code_block, = extract_braced(remaining.strip) if remaining
        next unless path_block && code_block
        [fname, path_block, code_block]
      end
    end

    def extract_braced(str)
      return [nil, nil] unless str.start_with?('{')
      depth = 0
      (0...str.length).each do |idx|
        ch = str[idx]
        depth += 1 if ch == '{'
        depth -= 1 if ch == '}'
        next unless depth.zero?
        inner = str[1...idx]
        remainder = str[(idx + 1)..]
        return [inner, remainder]
      end
      [nil, nil]
    end

    # -----------------------------
    # Command runner
    # -----------------------------
    def default_run_command(cmdline)
      stdout, stderr, status = Open3.capture3(cmdline)
      [stdout, stderr, status]
    end

    # -----------------------------
    # CLI
    # -----------------------------
    def usage
      <<~TXT
        Usage:
          ruby embgen.rb FILE ...
          ruby embgen.rb -r ROOT ... [-i PATTERN|--include=PAT] [-x PATTERN|--exclude=PAT]
          ruby embgen.rb -l LISTFILE
      TXT
    end

    def main(argv = ARGV)
      register_builtin_generators

      roots = []
      include_pats = []
      exclude_pats = []
      list_files = []
      files = []

      args = argv.dup
      until args.empty?
        arg = args.shift
        case arg
        when '-r'
          dir = args.shift or abort(usage)
          roots << dir
        when /\A--include=(.+)/
          include_pats << Regexp.last_match(1)
        when '--include', '-i'
          pat = args.shift or abort(usage)
          include_pats << pat
        when /\A--exclude=(.+)/
          exclude_pats << Regexp.last_match(1)
        when '--exclude', '-x'
          pat = args.shift or abort(usage)
          exclude_pats << pat
        when '-l'
          lf = args.shift or abort(usage)
          list_files << lf
        when /\A-/
          abort(usage)
        else
          files << arg
        end
      end

      include_pats = ['*'] if include_pats.empty?

      targets = []
      errors = 0

      roots.each do |root|
        unless File.directory?(root)
          Embgen.add_to_status("ROOTDIR is not a directory: #{root}")
          errors += 1
          next
        end
        collect_files(root, include_pats, exclude_pats, targets)
      end

      list_files.each { |lf| targets.concat(read_list_file(lf)) }
      files.each { |f| targets << File.expand_path(f) }

      targets = targets.uniq
      if targets.empty?
        if errors.positive?
          exit(1)
        else
          Embgen.add_to_status('no files to process')
          exit(0)
        end
      end

      targets.each do |t|
        unless File.file?(t)
          Embgen.add_to_status("skipping non-file: #{t}")
          errors += 1
          next
        end
        begin
          process_file(t)
        rescue StandardError => e
          errors += 1
          Embgen.add_to_status("error processing #{t}: #{e.message}")
        end
      end

      exit(1) if errors.positive?
    end

    private

    def warn_uuid_mismatch(filename, expected, found, stage)
      Embgen.add_to_status("UUID mismatch (#{stage}) in #{filename}: header=#{expected}, #{stage}=#{found}")
    end
  end

  # Run CLI if executed directly
  if $PROGRAM_NAME == __FILE__
    Engine.new.main(ARGV)
  end
end
