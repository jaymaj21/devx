import argparse
import csv
import os
import re
import shutil
import sys


DEFAULT_IMPORT_LINE = "import com.mprewriter.utils.*;"
DEFAULT_CALL = "mprewriter.scope_START({id});"


INJECTION_PATTERN = re.compile(
    r"""(
    \bdefault\s*: |
    \bcase\b\s+[^:]+: |
    (try|else|->|Exception)?\s*\)*\s*(//.*)?\s*\{
    )""",
    re.VERBOSE | re.DOTALL,
)

LEFT_SKIP_PATTERN = re.compile(
    r"((\bswitch\b)|(\binterface\b)|(new [A-Za-z_0-9]+[(][^)]*[)])|(\bclass\b)|(\benum\b))[^{;]*\{"
)

RIGHT_SKIP_PATTERN = re.compile(
    r"""^(([0-9"\}])|(mprewriter)|(\s*super\()|(\s*this\())"""
)

PACKAGE_PATTERN = re.compile(r"^\s*package\s+[^;]+;", re.MULTILINE)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description=(
            "Regex-based Java source instrumentation for CovForDistributedSystems. "
            "This edits source files directly and injects mprewriter.scope_START(id) calls."
        )
    )
    parser.add_argument(
        "input",
        help="Text file containing one Java source path per line, a single .java file, or a directory to scan recursively",
    )
    parser.add_argument("startlocid", type=int, help="First probe id to use")
    parser.add_argument(
        "--metadata",
        help="Write branch-probe-compatible CSV metadata: id,class,method,where,source,line",
    )
    parser.add_argument(
        "--grep-metadata",
        help="Write grep-style metadata lines: file:line: source text containing scope_START(id)",
    )
    parser.add_argument(
        "--call-template",
        default=DEFAULT_CALL,
        help="Injected call template. Must contain {id}. Default: %(default)s",
    )
    parser.add_argument(
        "--import-line",
        default=DEFAULT_IMPORT_LINE,
        help="Import line inserted after the package declaration. Use --no-import to suppress it.",
    )
    parser.add_argument(
        "--no-import",
        action="store_true",
        help="Do not insert an import line after the package declaration.",
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        help="Before modifying each source file, write <file>.uninstrumented backup if absent.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write source files; still print and optionally write metadata for the planned injections.",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print regex matching diagnostics.",
    )
    parser.add_argument(
        "--preserve-file-gap",
        action="store_true",
        help="Preserve old instr2.py behavior that skipped one probe id at the start of every file.",
    )
    args = parser.parse_args(argv)
    if "{id}" not in args.call_template:
        parser.error("--call-template must contain {id}")
    return args


def read_file_list(path):
    with open(path, "r", encoding="utf-8-sig") as filelistfp:
        return [line.strip() for line in filelistfp if line.strip()]


def discover_java_files(input_path):
    if os.path.isdir(input_path):
        results = []
        for root, dirnames, filenames in os.walk(input_path):
            dirnames.sort()
            for filename in sorted(filenames):
                if filename.lower().endswith(".java"):
                    results.append(os.path.join(root, filename))
        return results
    if os.path.isfile(input_path) and input_path.lower().endswith(".java"):
        return [input_path]
    return read_file_list(input_path)


def normalize_path(path):
    return path.replace("\\", "/")


def class_name_for_source(path, content):
    package_match = PACKAGE_PATTERN.search(content)
    package_name = package_match.group(0).split(None, 1)[1].rstrip(";") if package_match else ""
    simple_name = os.path.splitext(os.path.basename(path))[0]
    return f"{package_name}.{simple_name}" if package_name else simple_name


def method_hint_before(text):
    control_words = {
        "if",
        "for",
        "while",
        "switch",
        "catch",
        "try",
        "else",
        "do",
        "synchronized",
    }
    matches = list(
        re.finditer(
            r"(?m)^\s*(?:(?:public|protected|private|static|final|synchronized|native|abstract)\s+)*(?:[\w<>\[\], ?]+\s+)?(\w+)\s*\([^;{}]*\)\s*(?:throws\s+[^{]+)?\{",
            text,
        )
    )
    for match in reversed(matches):
        name = match.group(1)
        if name not in control_words:
            return name
    return ""


def insert_import(content, import_line):
    if not import_line:
        return content, 0
    if import_line in content:
        return content, 0
    match = PACKAGE_PATTERN.search(content)
    if not match:
        return content, 0
    insertion = "\n" + import_line + "\n"
    return content[: match.end()] + insertion + content[match.end() :], len(insertion)


def source_line_at(content, index):
    return content.count("\n", 0, index) + 1


def instrument_content(filename, content, next_id, args):
    content, import_delta = insert_import(content, None if args.no_import else args.import_line)
    remaining = content
    reassembled = ""
    offset = 0
    metadata = []
    class_name = class_name_for_source(filename, content)

    if args.preserve_file_gap:
        next_id += 1

    while True:
        match = INJECTION_PATTERN.search(remaining)
        if match is None:
            break

        firstpart = remaining[: match.end()]
        absolute_end = offset + match.end()
        remaining = remaining[match.end() :]

        leftmatch = LEFT_SKIP_PATTERN.search(firstpart)
        right_window = remaining[1:] if len(remaining) > 1 else ""
        rightmatch = RIGHT_SKIP_PATTERN.search(right_window)

        if args.debug:
            print("STARTLOCID=" + str(next_id))
            print("file=" + filename)
            print("line=" + str(source_line_at(content, absolute_end)))
            print("firstpart=[[" + (firstpart or "None") + "]]")
            print("remaining=[[" + (remaining[:200] or "None") + "]]")
            print("leftmatch=[[" + str(leftmatch or "None") + "]]")
            print("rightmatch=[[" + str(rightmatch or "None") + "]]")

        reassembled += firstpart
        if leftmatch is None and rightmatch is None:
            call = " " + args.call_template.format(id=next_id)
            line = source_line_at(content, absolute_end)
            method = method_hint_before(content[:absolute_end])
            reassembled += call
            metadata.append(
                {
                    "id": next_id,
                    "class": class_name,
                    "method": method,
                    "where": "SOURCE_SCOPE_START",
                    "source": os.path.basename(filename),
                    "line": line,
                    "path": normalize_path(filename),
                    "grep_line": f"{normalize_path(filename)}:{line}:{call.strip()}",
                }
            )
            next_id += 1

        offset = absolute_end

    reassembled += remaining
    return reassembled, metadata, next_id, import_delta


def write_metadata(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=["id", "class", "method", "where", "source", "line"])
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row[key] for key in writer.fieldnames})


def write_grep_metadata(path, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as fp:
        for row in rows:
            fp.write(row["grep_line"] + "\n")


def instrument_file(filename, next_id, args):
    print("Instrumenting file " + filename)
    with open(filename, "r", encoding="utf-8-sig") as fp:
        content = fp.read()

    new_content, metadata, next_id, _ = instrument_content(filename, content, next_id, args)

    if not args.dry_run and new_content != content:
        if args.backup:
            backup_path = filename + ".uninstrumented"
            if not os.path.exists(backup_path):
                shutil.copy2(filename, backup_path)
        with open(filename, "w", encoding="utf-8", newline="") as fp:
            fp.write(new_content)

    print(f"  probes={len(metadata)}")
    return metadata, next_id


def main(argv):
    args = parse_args(argv)
    files = discover_java_files(args.input)
    next_id = args.startlocid
    all_metadata = []

    for filename in files:
        metadata, next_id = instrument_file(filename, next_id, args)
        all_metadata.extend(metadata)

    if args.metadata:
        write_metadata(args.metadata, all_metadata)
    if args.grep_metadata:
        write_grep_metadata(args.grep_metadata, all_metadata)

    print("Total files instrumented:", len(files))
    print("Total probes inserted:", len(all_metadata))
    print("LAST_ID=" + str(next_id - 1))


if __name__ == "__main__":
    main(sys.argv[1:])
