#!/usr/bin/env tclsh

namespace eval ::tdstr {
    variable envCounter 0
}

proc ::tdstr::main {} {
    if {[catch {
        set args $::argv
        if {[llength $args] == 0 || [lsearch -exact $args "--help"] >= 0 || [lsearch -exact $args "-h"] >= 0} {
            ::tdstr::printUsage
            exit [expr {[llength $args] == 0 ? 1 : 0}]
        }
        if {[llength $args] == 1} {
            ::tdstr::compileInputPath [lindex $args 0] ""
        } elseif {[llength $args] == 2} {
            ::tdstr::compileInputPath [lindex $args 0] [lindex $args 1]
        } else {
            error "Expected one input path and an optional output path."
        }
    } message options]} {
        puts stderr "Error: $message"
        if {[dict exists $options -errorinfo]} {
            puts stderr [dict get $options -errorinfo]
        }
        exit 1
    }
}

proc ::tdstr::printUsage {} {
    puts stderr "Usage: tclsh scripts/tdstr-dsl-compiler.tcl <input.tdstr|directory> ?output.json|directory?"
}

proc ::tdstr::compileInputPath {input output} {
    set inputPath [file normalize $input]
    if {[file isdirectory $inputPath]} {
        ::tdstr::compileDirectory $inputPath $output
        return
    }
    if {[string equal -nocase [file extension $inputPath] ".tdstr"]} {
        ::tdstr::compileOneFile $inputPath $output
        return
    }
    error "Input must be a .tdstr file or a directory, got $inputPath"
}

proc ::tdstr::compileDirectory {inputDir outputDir} {
    if {$outputDir eq ""} {
        set targetDir $inputDir
    } else {
        set targetDir $outputDir
    }
    set targetDir [file normalize $targetDir]
    file mkdir $targetDir

    set files [lsort [glob -nocomplain -directory $inputDir *.tdstr]]
    if {[llength $files] == 0} {
        error "No .tdstr files found under $inputDir"
    }

    foreach file $files {
        set outputFile [file join $targetDir "[file rootname [file tail $file]].json"]
        ::tdstr::compileOneFile $file $outputFile
    }
}

proc ::tdstr::compileOneFile {inputFile outputFile} {
    set inputFile [file normalize $inputFile]
    if {$outputFile eq ""} {
        set outputFile "[file rootname $inputFile].json"
    }
    set outputFile [file normalize $outputFile]

    set ns [::tdstr::newEnv $inputFile]
    if {[catch {
        ::tdstr::envSource $ns $inputFile
        set compiled [::tdstr::stateGet $ns compiledSpec ""]
        if {$compiled eq ""} {
            error "File $inputFile must contain a top-level system command"
        }
        file mkdir [file dirname $outputFile]
        set channel [open $outputFile w]
        puts -nonewline $channel [::tdstr::writeJson $compiled 0]
        puts $channel ""
        close $channel
        puts "Wrote $outputFile"
    } message options]} {
        ::tdstr::destroyEnv $ns
        return -options $options $message
    }
    ::tdstr::destroyEnv $ns
}

proc ::tdstr::newEnv {inputFile} {
    variable envCounter
    incr envCounter
    set ns "::tdstr::env$envCounter"
    namespace eval $ns {}

    set state [dict create \
        currentFile $inputFile \
        currentDir [file dirname $inputFile] \
        sourceDirStack {} \
        systemSeen 0 \
        systemName "" \
        variables {} \
        domains {} \
        rawInit {} \
        rawActions {} \
        rawNext {} \
        rawInvariants {} \
        rawProperties {} \
        javaEnums {} \
        compiledSpec ""]
    set ${ns}::state $state

    foreach command {system vars vars* domain domain* init action next invariant property same unchanged load-java-enums load-proto-enums} {
        proc ${ns}::${command} {args} [format {eval [linsert $args 0 ::tdstr::%s {%s}]} $command $ns]
    }
    proc ${ns}::source {path} [format {::tdstr::envSource {%s} $path} $ns]

    return $ns
}

proc ::tdstr::destroyEnv {ns} {
    catch {namespace delete $ns}
}

proc ::tdstr::envSource {ns path} {
    set stack [::tdstr::stateGet $ns sourceDirStack {}]
    if {[llength $stack] == 0} {
        set base [::tdstr::stateGet $ns currentDir [pwd]]
    } else {
        set base [lindex $stack end]
    }

    if {[file pathtype $path] eq "absolute"} {
        set resolved [file normalize $path]
    } else {
        set resolved [file normalize [file join $base $path]]
    }
    if {![file exists $resolved]} {
        error "Source file not found: $resolved"
    }

    ::tdstr::stateSet $ns sourceDirStack [concat $stack [list [file dirname $resolved]]]

    set channel [open $resolved r]
    set script [read $channel]
    close $channel

    set code [catch {namespace eval $ns $script} result options]

    set stack [::tdstr::stateGet $ns sourceDirStack {}]
    ::tdstr::stateSet $ns sourceDirStack [lrange $stack 0 end-1]

    if {$code} {
        return -options $options $result
    }
    return $result
}

proc ::tdstr::stateGet {ns key defaultValue} {
    upvar #0 ${ns}::state state
    if {[dict exists $state $key]} {
        return [dict get $state $key]
    }
    return $defaultValue
}

proc ::tdstr::stateSet {ns key value} {
    upvar #0 ${ns}::state state
    dict set state $key $value
    return $value
}

proc ::tdstr::system {ns args} {
    if {[llength $args] != 2} {
        error "system expects a name and a body script"
    }
    if {[::tdstr::stateGet $ns systemSeen 0]} {
        error "Only one top-level system command is allowed"
    }

    set name [lindex $args 0]
    set body [lindex $args 1]
    ::tdstr::stateSet $ns systemSeen 1
    ::tdstr::stateSet $ns systemName $name

    namespace eval $ns $body

    set compiled [::tdstr::finalizeSystem $ns]
    ::tdstr::stateSet $ns compiledSpec $compiled
    return ""
}

proc ::tdstr::vars {ns args} {
    if {[llength $args] == 0} {
        error "vars requires at least one variable"
    }
    if {[llength [::tdstr::stateGet $ns variables {}]] > 0} {
        error "Only one vars clause is allowed"
    }

    set seen {}
    foreach var $args {
        set name [::tdstr::dslName $var]
        if {[lsearch -exact $seen $name] >= 0} {
            error "Duplicate variable name in vars clause: $name"
        }
        lappend seen $name
    }
    ::tdstr::stateSet $ns variables $seen
    return ""
}

proc ::tdstr::vars* {ns args} {
    if {[llength $args] != 4 || [lindex $args 2] ne "*"} {
        error "vars* expects: vars* separator {group1 ...} * {group2 ...}"
    }
    if {[llength [::tdstr::stateGet $ns variables {}]] > 0} {
        error "Only one vars clause is allowed"
    }

    set separator [lindex $args 0]
    set leftGroup [lindex $args 1]
    set rightGroup [lindex $args 3]

    if {[llength $leftGroup] == 0 || [llength $rightGroup] == 0} {
        error "vars* requires two non-empty groups"
    }

    set generated {}
    foreach left $leftGroup {
        foreach right $rightGroup {
            set name [::tdstr::dslName "${left}${separator}${right}"]
            if {[lsearch -exact $generated $name] >= 0} {
                error "Duplicate variable name generated by vars*: $name"
            }
            lappend generated $name
        }
    }
    ::tdstr::stateSet $ns variables $generated
    return ""
}

proc ::tdstr::domain {ns args} {
    if {[llength $args] < 2} {
        error "domain requires a variable and at least one value or expression"
    }

    set variable [::tdstr::dslName [lindex $args 0]]
    set body [lrange $args 1 end]
    set domains [::tdstr::stateGet $ns domains {}]

    if {[dict exists $domains $variable]} {
        error "Duplicate domain clause for variable $variable"
    }

    dict set domains $variable $body
    ::tdstr::stateSet $ns domains $domains
    return ""
}

proc ::tdstr::domain* {ns args} {
    if {[llength $args] < 2} {
        error "domain* requires a pattern and at least one value or expression"
    }

    set pattern [::tdstr::dslName [lindex $args 0]]
    set body [lrange $args 1 end]
    set variables [::tdstr::stateGet $ns variables {}]
    if {[llength $variables] == 0} {
        error "domain* requires vars or vars* to be declared first"
    }

    set matches {}
    foreach variable $variables {
        if {[string match $pattern $variable]} {
            lappend matches $variable
        }
    }
    if {[llength $matches] == 0} {
        error "domain* pattern matched no declared variables: $pattern"
    }

    set domains [::tdstr::stateGet $ns domains {}]
    foreach variable $matches {
        if {[dict exists $domains $variable]} {
            error "Duplicate domain clause for variable $variable via domain*"
        }
        dict set domains $variable $body
    }
    ::tdstr::stateSet $ns domains $domains
    return ""
}

proc ::tdstr::init {ns args} {
    if {[llength $args] == 0} {
        error "init requires at least one expression"
    }
    if {[llength [::tdstr::stateGet $ns rawInit {}]] > 0} {
        error "Only one init clause is allowed"
    }
    ::tdstr::stateSet $ns rawInit $args
    return ""
}

proc ::tdstr::action {ns args} {
    if {[llength $args] < 2} {
        error "action requires a name and at least one body expression"
    }
    set actions [::tdstr::stateGet $ns rawActions {}]
    lappend actions [list [::tdstr::dslName [lindex $args 0]] [lrange $args 1 end]]
    ::tdstr::stateSet $ns rawActions $actions
    return ""
}

proc ::tdstr::next {ns args} {
    if {[llength $args] == 0} {
        error "next requires at least one expression"
    }
    if {[llength [::tdstr::stateGet $ns rawNext {}]] > 0} {
        error "Only one next clause is allowed"
    }
    ::tdstr::stateSet $ns rawNext $args
    return ""
}

proc ::tdstr::invariant {ns args} {
    if {[llength $args] < 2} {
        error "invariant requires a name and at least one body expression"
    }
    set invariants [::tdstr::stateGet $ns rawInvariants {}]
    lappend invariants [list [::tdstr::dslName [lindex $args 0]] [lrange $args 1 end]]
    ::tdstr::stateSet $ns rawInvariants $invariants
    return ""
}

proc ::tdstr::property {ns args} {
    if {[llength $args] < 2} {
        error "property requires a name and at least one body expression"
    }
    set properties [::tdstr::stateGet $ns rawProperties {}]
    lappend properties [list [::tdstr::dslName [lindex $args 0]] [lrange $args 1 end]]
    ::tdstr::stateSet $ns rawProperties $properties
    return ""
}

proc ::tdstr::same {ns args} {
    if {[llength $args] != 1} {
        error "same expects exactly one variable name"
    }
    set variable [::tdstr::dslName [lindex $args 0]]
    return [list = "${variable}+" $variable]
}

proc ::tdstr::unchanged {ns args} {
    set clauses {}
    foreach variable $args {
        lappend clauses [::tdstr::same $ns $variable]
    }
    return $clauses
}

proc ::tdstr::load-java-enums {ns args} {
    if {[llength $args] == 0} {
        error "load-java-enums expects at least one Java file or directory"
    }
    foreach path $args {
        ::tdstr::loadJavaEnumsFromPath $ns [::tdstr::resolveEnvPath $ns $path]
    }
    return ""
}

proc ::tdstr::load-proto-enums {ns args} {
    if {[llength $args] == 0} {
        error "load-proto-enums expects at least one proto file or directory"
    }
    foreach path $args {
        ::tdstr::loadProtoEnumsFromPath $ns [::tdstr::resolveEnvPath $ns $path]
    }
    return ""
}

proc ::tdstr::resolveEnvPath {ns path} {
    set stack [::tdstr::stateGet $ns sourceDirStack {}]
    if {[llength $stack] == 0} {
        set base [::tdstr::stateGet $ns currentDir [pwd]]
    } else {
        set base [lindex $stack end]
    }
    if {[file pathtype $path] eq "absolute"} {
        return [file normalize $path]
    }
    return [file normalize [file join $base $path]]
}

proc ::tdstr::loadJavaEnumsFromPath {ns path} {
    if {[file isdirectory $path]} {
        foreach file [::tdstr::recursiveJavaFiles $path] {
            ::tdstr::loadJavaEnumsFromFile $ns $file
        }
        return
    }
    if {[file exists $path]} {
        ::tdstr::loadJavaEnumsFromFile $ns $path
        return
    }
    error "Java enum path not found: $path"
}

proc ::tdstr::loadProtoEnumsFromPath {ns path} {
    if {[file isdirectory $path]} {
        foreach file [::tdstr::recursiveFilesWithExtension $path ".proto"] {
            ::tdstr::loadProtoEnumsFromFile $ns $file
        }
        return
    }
    if {[file exists $path]} {
        ::tdstr::loadProtoEnumsFromFile $ns $path
        return
    }
    error "Proto enum path not found: $path"
}

proc ::tdstr::recursiveJavaFiles {dir} {
    return [::tdstr::recursiveFilesWithExtension $dir ".java"]
}

proc ::tdstr::recursiveFilesWithExtension {dir extension} {
    set result {}
    foreach entry [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [::tdstr::recursiveFilesWithExtension $entry $extension]]
        } elseif {[string equal -nocase [file extension $entry] $extension]} {
            lappend result [file normalize $entry]
        }
    }
    return $result
}

proc ::tdstr::loadJavaEnumsFromFile {ns path} {
    if {![string equal -nocase [file extension $path] ".java"]} {
        return
    }
    set channel [open $path r]
    set content [read $channel]
    close $channel
    foreach enum [::tdstr::parseJavaEnums [::tdstr::stripJavaComments $content]] {
        set name [string tolower [lindex $enum 0]]
        set values {}
        foreach value [lindex $enum 1] {
            lappend values [string tolower $value]
        }
        set javaEnums [::tdstr::stateGet $ns javaEnums {}]
        dict set javaEnums $name $values
        ::tdstr::stateSet $ns javaEnums $javaEnums
    }
}

proc ::tdstr::loadProtoEnumsFromFile {ns path} {
    if {![string equal -nocase [file extension $path] ".proto"]} {
        return
    }
    set channel [open $path r]
    set content [read $channel]
    close $channel
    foreach enum [::tdstr::parseProtoEnums [::tdstr::stripJavaComments $content]] {
        set name [string tolower [lindex $enum 0]]
        set values {}
        foreach value [lindex $enum 1] {
            lappend values [string tolower $value]
        }
        set javaEnums [::tdstr::stateGet $ns javaEnums {}]
        dict set javaEnums $name $values
        ::tdstr::stateSet $ns javaEnums $javaEnums
    }
}

proc ::tdstr::stripJavaComments {text} {
    set out ""
    set i 0
    set len [string length $text]
    while {$i < $len} {
        set ch [string index $text $i]
        set next [expr {$i + 1 < $len ? [string index $text [expr {$i + 1}]] : ""}]
        if {$ch eq "/" && $next eq "/"} {
            incr i 2
            while {$i < $len && [string first [string index $text $i] "\n\r"] < 0} {
                incr i
            }
        } elseif {$ch eq "/" && $next eq "*"} {
            incr i 2
            while {$i + 1 < $len && !([string index $text $i] eq "*" && [string index $text [expr {$i + 1}]] eq "/")} {
                incr i
            }
            incr i 2
        } else {
            append out $ch
            incr i
        }
    }
    return $out
}

proc ::tdstr::parseJavaEnums {text} {
    set result {}
    set start 0
    while {[regexp -indices -start $start {enum[ \t\r\n]+([A-Za-z_$][A-Za-z0-9_$]*)} $text match nameRange]} {
        set enumName [string range $text [lindex $nameRange 0] [lindex $nameRange 1]]
        set searchFrom [expr {[lindex $match 1] + 1}]
        set bracePos [string first "\{" $text $searchFrom]
        if {$bracePos < 0} {
            set start $searchFrom
            continue
        }
        set endPos [::tdstr::findMatchingBrace $text $bracePos]
        if {$endPos < 0} {
            set start [expr {$bracePos + 1}]
            continue
        }
        set body [string range $text [expr {$bracePos + 1}] [expr {$endPos - 1}]]
        lappend result [list $enumName [::tdstr::parseJavaEnumConstants $body]]
        set start [expr {$endPos + 1}]
    }
    return $result
}

proc ::tdstr::findMatchingBrace {text openIndex} {
    set depth 0
    for {set i $openIndex} {$i < [string length $text]} {incr i} {
        set ch [string index $text $i]
        if {$ch eq "\{"} {
            incr depth
        } elseif {$ch eq "\}"} {
            incr depth -1
            if {$depth == 0} {
                return $i
            }
        }
    }
    return -1
}

proc ::tdstr::parseJavaEnumConstants {body} {
    set semi [string first ";" $body]
    if {$semi >= 0} {
        set body [string range $body 0 [expr {$semi - 1}]]
    }
    set values {}
    foreach part [split $body ,] {
        set trimmed [string trim $part]
        if {[regexp {^([A-Za-z_$][A-Za-z0-9_$]*)} $trimmed -> value]} {
            lappend values $value
        }
    }
    return $values
}

proc ::tdstr::parseProtoEnums {text} {
    set result {}
    set start 0
    while {[regexp -indices -start $start {(^|[^A-Za-z0-9_$])enum[ \t\r\n]+([A-Za-z_$][A-Za-z0-9_$]*)} $text match _ nameRange]} {
        set enumName [string range $text [lindex $nameRange 0] [lindex $nameRange 1]]
        set searchFrom [expr {[lindex $match 1] + 1}]
        set bracePos [string first "\{" $text $searchFrom]
        if {$bracePos < 0} {
            set start $searchFrom
            continue
        }
        set endPos [::tdstr::findMatchingBrace $text $bracePos]
        if {$endPos < 0} {
            set start [expr {$bracePos + 1}]
            continue
        }
        set body [string range $text [expr {$bracePos + 1}] [expr {$endPos - 1}]]
        lappend result [list $enumName [::tdstr::parseProtoEnumConstants $body]]
        set start [expr {$endPos + 1}]
    }
    return $result
}

proc ::tdstr::parseProtoEnumConstants {body} {
    set values {}
    foreach statement [split $body ";"] {
        set trimmed [string trim $statement]
        if {[regexp {^([A-Za-z_$][A-Za-z0-9_$]*)[ \t\r\n]*=} $trimmed -> value]} {
            set lowered [string tolower $value]
            if {$lowered ne "option" && $lowered ne "reserved"} {
                lappend values $value
            }
        }
    }
    return $values
}

proc ::tdstr::finalizeSystem {ns} {
    set name [::tdstr::dslName [::tdstr::stateGet $ns systemName ""]]
    set variables [::tdstr::stateGet $ns variables {}]
    set domains [::tdstr::stateGet $ns domains {}]
    set rawInit [::tdstr::stateGet $ns rawInit {}]
    set rawActions [::tdstr::stateGet $ns rawActions {}]
    set rawNext [::tdstr::stateGet $ns rawNext {}]
    set rawInvariants [::tdstr::stateGet $ns rawInvariants {}]
    set rawProperties [::tdstr::stateGet $ns rawProperties {}]
    set javaEnums [::tdstr::stateGet $ns javaEnums {}]

    if {[llength $variables] == 0} {
        error "system requires a vars clause"
    }
    if {[llength $rawInit] == 0} {
        error "system requires an init clause"
    }
    if {[llength $rawNext] == 0} {
        error "system requires a next clause"
    }

    foreach variable $variables {
        if {![dict exists $domains $variable]} {
            error "Missing domain clause for variable $variable"
        }
    }

    set actionNames {}
    foreach action $rawActions {
        set actionName [lindex $action 0]
        if {[lsearch -exact $actionNames $actionName] >= 0} {
            error "Duplicate action name: $actionName"
        }
        lappend actionNames $actionName
    }

    set context [dict create variables $variables actions $actionNames locals {} javaEnums $javaEnums]

    set domainPairs {}
    foreach variable $variables {
        lappend domainPairs [list $variable [::tdstr::compileDomain [dict get $domains $variable] $context]]
    }

    set initNode [::tdstr::compileBody $rawInit $context 0 0]
    set nextNode [::tdstr::compileBody $rawNext $context 1 1]

    set actionNodes {}
    foreach action $rawActions {
        set actionName [lindex $action 0]
        set bodyForms [lindex $action 1]
        lappend actionNodes [::tdstr::namedBodyNode $actionName [::tdstr::compileBody $bodyForms $context 1 0]]
    }

    set invariantNodes {}
    foreach invariant $rawInvariants {
        lappend invariantNodes [::tdstr::namedBodyNode [lindex $invariant 0] [::tdstr::compileBody [lindex $invariant 1] $context 0 0]]
    }

    set propertyNodes {}
    foreach property $rawProperties {
        lappend propertyNodes [::tdstr::namedBodyNode [lindex $property 0] [::tdstr::compileBody [lindex $property 1] $context 0 0]]
    }

    set removableVariables [::tdstr::findRemovableVariables $variables $initNode $actionNodes $nextNode $invariantNodes $propertyNodes]
    if {[llength $removableVariables] > 0} {
        set keptVariables {}
        foreach variable $variables {
            if {[lsearch -exact $removableVariables $variable] < 0} {
                lappend keptVariables $variable
            }
        }
        set variables $keptVariables

        set keptDomainPairs {}
        foreach pair $domainPairs {
            if {[lsearch -exact $removableVariables [lindex $pair 0]] < 0} {
                lappend keptDomainPairs $pair
            }
        }
        set domainPairs $keptDomainPairs

        set initNode [::tdstr::stripRemovableVariables $initNode $removableVariables 1]
        set nextNode [::tdstr::stripRemovableVariables $nextNode $removableVariables 0]
        set actionNodes [::tdstr::stripRemovableVariablesFromNamedBodies $actionNodes $removableVariables]
        set invariantNodes [::tdstr::stripRemovableVariablesFromNamedBodies $invariantNodes $removableVariables]
        set propertyNodes [::tdstr::stripRemovableVariablesFromNamedBodies $propertyNodes $removableVariables]
    }

    return [list object \
        [list name [::tdstr::jsonString $name]] \
        [list variables [::tdstr::jsonArrayFromStrings $variables]] \
        [list domains [::tdstr::jsonObject $domainPairs]] \
        [list init $initNode] \
        [list actions [::tdstr::jsonArrayNode $actionNodes]] \
        [list next $nextNode] \
        [list invariants [::tdstr::jsonArrayNode $invariantNodes]] \
        [list properties [::tdstr::jsonArrayNode $propertyNodes]]]
}

proc ::tdstr::compileDomain {forms context} {
    if {[llength $forms] == 1 && [::tdstr::javaEnumDomainTokenP [lindex $forms 0]]} {
        return [::tdstr::compileJavaEnumDomain [lindex $forms 0] $context]
    }
    if {[llength $forms] == 1 && [::tdstr::looksLikeExprList [lindex $forms 0]]} {
        return [::tdstr::compileExpr [lindex $forms 0] $context 0 0 0]
    }

    set elements {}
    foreach form $forms {
        lappend elements [::tdstr::compileExpr $form $context 0 0 1]
    }
    return [list object [list set [::tdstr::jsonArrayNode $elements]]]
}

proc ::tdstr::javaEnumDomainTokenP {token} {
    set name [::tdstr::dslName $token]
    return [expr {[string length $name] > 1 && [string index $name 0] eq "@"}]
}

proc ::tdstr::compileJavaEnumDomain {token context} {
    set enumName [string range [::tdstr::dslName $token] 1 end]
    set javaEnums [dict get $context javaEnums]
    if {![dict exists $javaEnums $enumName]} {
        error "Unknown Java enum domain reference @$enumName"
    }
    set elements {}
    foreach value [dict get $javaEnums $enumName] {
        lappend elements [list object [list lit [::tdstr::jsonString $value]]]
    }
    return [list object [list set [::tdstr::jsonArrayNode $elements]]]
}

proc ::tdstr::compileBody {forms context allowNext allowActionRef} {
    if {[llength $forms] == 0} {
        error "Clause body cannot be empty"
    }
    if {[llength $forms] == 1} {
        return [::tdstr::compileExpr [lindex $forms 0] $context $allowNext $allowActionRef 0]
    }

    set args {}
    foreach form $forms {
        lappend args [::tdstr::compileExpr $form $context $allowNext $allowActionRef 0]
    }
    return [list object [list and [::tdstr::jsonArrayNode $args]]]
}

proc ::tdstr::compileExpr {form context allowNext allowActionRef domainLiterals} {
    set length [llength $form]
    if {$length == 0} {
        error "Unsupported empty expression"
    }
    if {$length == 1} {
        return [::tdstr::compileAtom [lindex $form 0] $context $allowNext $allowActionRef $domainLiterals]
    }

    set head [::tdstr::dslName [lindex $form 0]]
    if {$head eq "alternate-scenarios"} {
        set head "or"
    }
    set tail [lrange $form 1 end]

    if {$head eq "quote"} {
        if {$length != 2} {
            error "quote expects exactly one argument, got $form"
        }
        return [list object [list lit [::tdstr::literalNode [lindex $form 1] 1]]]
    }
    if {$head eq "set"} {
        if {$length == 4 && [::tdstr::dslName [lindex $form 2]] eq "as"} {
            return [::tdstr::compileSetAs $tail $context $allowNext $allowActionRef]
        }
        set elements {}
        foreach arg $tail {
            lappend elements [::tdstr::compileExpr $arg $context $allowNext $allowActionRef 0]
        }
        return [list object [list set [::tdstr::jsonArrayNode $elements]]]
    }
    if {$head eq "not" || $head eq "eventually"} {
        if {$length != 2} {
            error "$head expects exactly one argument, got $form"
        }
        return [list object [list $head [::tdstr::compileExpr [lindex $form 1] $context $allowNext $allowActionRef 0]]]
    }
    if {$head eq "if"} {
        return [::tdstr::compileIfThen $tail $context $allowNext $allowActionRef]
    }
    if {$head eq "assign"} {
        return [::tdstr::compileAssign $tail $context $allowNext $allowActionRef]
    }
    if {$head eq "equals"} {
        return [::tdstr::compileEquals $tail $context $allowNext $allowActionRef]
    }
    if {$head eq "unchanged*"} {
        return [::tdstr::compileUnchangedStar $tail $context]
    }
    if {$head eq "forall" || $head eq "exists"} {
        return [::tdstr::compileQuantified $head $tail $context $allowNext $allowActionRef]
    }
    if {[lsearch -exact {and or + - * / = != < <= > >= in implies} $head] >= 0} {
        return [::tdstr::compileOperator $head $tail $context $allowNext $allowActionRef]
    }

    error "Unsupported expression form $form"
}

proc ::tdstr::compileAtom {token context allowNext allowActionRef domainLiterals} {
    set literalNode [::tdstr::maybeLiteralNode $token]
    if {$literalNode ne ""} {
        return [list object [list lit $literalNode]]
    }
    if {$domainLiterals} {
        return [list object [list lit [::tdstr::jsonString [::tdstr::dslName $token]]]]
    }

    set name [::tdstr::dslName $token]
    set variables [dict get $context variables]
    set locals [dict get $context locals]
    set actions [dict get $context actions]

    if {[lsearch -exact $locals $name] >= 0 || [lsearch -exact $variables $name] >= 0} {
        return [list object [list var [::tdstr::jsonString $name]]]
    }
    if {$allowNext && [::tdstr::plusSuffixedNameP $name]} {
        set base [string range $name 0 end-1]
        if {[lsearch -exact $variables $base] >= 0} {
            return [list object [list next [::tdstr::jsonString $base]]]
        }
    }
    if {$allowActionRef && [string index $name 0] eq "@"} {
        set actionName [string range $name 1 end]
        if {[lsearch -exact $actions $actionName] >= 0} {
            return [list object [list actionRef [::tdstr::jsonString $actionName]]]
        }
    }

    return [list object [list lit [::tdstr::jsonString $name]]]
}

proc ::tdstr::compileQuantified {operator args context allowNext allowActionRef} {
    if {[llength $args] == 2} {
        set binding [lindex $args 0]
        set body [lindex $args 1]
        if {[llength $binding] != 3 || [::tdstr::dslName [lindex $binding 1]] ne "in"} {
            error "$operator binding must look like {var in domain}, got $binding"
        }
        set variable [::tdstr::dslName [lindex $binding 0]]
        set domainExpr [lindex $binding 2]
    } elseif {[llength $args] == 4 && [::tdstr::dslName [lindex $args 1]] eq "in"} {
        set variable [::tdstr::dslName [lindex $args 0]]
        set domainExpr [lindex $args 2]
        set body [lindex $args 3]
    } else {
        error "$operator expects either {var in domain} body or var in domain body"
    }

    set nextContext $context
    dict set nextContext locals [concat [dict get $context locals] [list $variable]]

    return [list object [list $operator [list object \
        [list var [::tdstr::jsonString $variable]] \
        [list in [::tdstr::compileExpr $domainExpr $context $allowNext $allowActionRef 0]] \
        [list body [::tdstr::compileExpr $body $nextContext $allowNext $allowActionRef 0]]]]]
}

proc ::tdstr::compileIfThen {args context allowNext allowActionRef} {
    if {[llength $args] != 3 || [::tdstr::dslName [lindex $args 1]] ne "then"} {
        error "if expects the form {if condition then consequence}"
    }

    set condition [::tdstr::compileIfBranch [lindex $args 0] $context $allowNext $allowActionRef]
    set consequence [::tdstr::compileIfBranch [lindex $args 2] $context $allowNext $allowActionRef]
    return [list object [list and [::tdstr::jsonArrayNode [list $condition $consequence]]]]
}

proc ::tdstr::compileIfBranch {form context allowNext allowActionRef} {
    if {[::tdstr::isImplicitAndBlock $form]} {
        return [::tdstr::compileBody $form $context $allowNext $allowActionRef]
    }
    return [::tdstr::compileExpr $form $context $allowNext $allowActionRef 0]
}

proc ::tdstr::compileAssign {args context allowNext allowActionRef} {
    if {[llength $args] != 3 || [::tdstr::dslName [lindex $args 1]] ne "to"} {
        error "assign expects the form {assign value to variable}"
    }

    return [::tdstr::compileNextAssignment [lindex $args 2] [lindex $args 0] $context $allowNext $allowActionRef "assign"]
}

proc ::tdstr::compileSetAs {args context allowNext allowActionRef} {
    if {[llength $args] != 3 || [::tdstr::dslName [lindex $args 1]] ne "as"} {
        error "set-as expects the form {set variable as value}"
    }

    return [::tdstr::compileNextAssignment [lindex $args 0] [lindex $args 2] $context $allowNext $allowActionRef "set-as"]
}

proc ::tdstr::compileNextAssignment {targetToken valueForm context allowNext allowActionRef formName} {
    set targetName [::tdstr::dslName $targetToken]
    set variables [dict get $context variables]
    if {[lsearch -exact $variables $targetName] < 0} {
        error "$formName target must be a declared variable name, got $targetToken"
    }

    set left [list object [list next [::tdstr::jsonString $targetName]]]
    set right [::tdstr::compileExpr $valueForm $context $allowNext $allowActionRef 0]
    return [list object [list = [::tdstr::jsonArrayNode [list $left $right]]]]
}

proc ::tdstr::compileEquals {args context allowNext allowActionRef} {
    if {[llength $args] != 2} {
        error "equals expects exactly two arguments"
    }

    set left [::tdstr::compileExpr [lindex $args 0] $context $allowNext $allowActionRef 0]
    set right [::tdstr::compileExpr [lindex $args 1] $context $allowNext $allowActionRef 0]
    return [list object [list = [::tdstr::jsonArrayNode [list $left $right]]]]
}

proc ::tdstr::compileUnchangedStar {args context} {
    if {[llength $args] == 0} {
        error "unchanged* expects at least one glob pattern"
    }

    set variables [dict get $context variables]
    set seen {}
    set clauses {}

    foreach pattern $args {
        set normalizedPattern [::tdstr::dslName $pattern]
        set matched 0
        foreach variable $variables {
            if {[string match $normalizedPattern $variable]} {
                set matched 1
                if {[lsearch -exact $seen $variable] >= 0} {
                    continue
                }
                lappend seen $variable
                set left [list object [list next [::tdstr::jsonString $variable]]]
                set right [list object [list var [::tdstr::jsonString $variable]]]
                lappend clauses [list object [list = [::tdstr::jsonArrayNode [list $left $right]]]]
            }
        }
        if {!$matched} {
            error "unchanged* pattern matched no declared variables: $pattern"
        }
    }

    return [list object [list and [::tdstr::jsonArrayNode $clauses]]]
}

proc ::tdstr::compileOperator {operator args context allowNext allowActionRef} {
    set compiledArgs {}
    foreach arg $args {
        lappend compiledArgs [::tdstr::compileExpr $arg $context $allowNext $allowActionRef 0]
    }

    if {[lsearch -exact {= != < <= > >= in implies} $operator] >= 0} {
        if {[llength $compiledArgs] != 2} {
            error "$operator expects exactly two arguments"
        }
        return [list object [list $operator [::tdstr::jsonArrayNode [list [lindex $compiledArgs 0] [lindex $compiledArgs 1]]]]]
    }

    if {[llength $compiledArgs] == 0} {
        error "$operator expects at least one argument"
    }
    if {$operator eq "/" && [llength $compiledArgs] != 2} {
        error "/ expects exactly two arguments"
    }

    return [list object [list $operator [::tdstr::jsonArrayNode $compiledArgs]]]
}

proc ::tdstr::maybeLiteralNode {token} {
    set text [::tdstr::dslName $token]
    if {$text eq "true" || $text eq "t"} {
        return [::tdstr::jsonBoolean 1]
    }
    if {$text eq "false" || $text eq "nil"} {
        return [::tdstr::jsonBoolean 0]
    }
    if {[string is integer -strict $text]} {
        return [::tdstr::jsonNumber $text]
    }
    if {[string is double -strict $text]} {
        return [::tdstr::jsonNumber $text]
    }
    return ""
}

proc ::tdstr::namedBodyNode {name bodyNode} {
    return [list object \
        [list name [::tdstr::jsonString $name]] \
        [list body $bodyNode]]
}

proc ::tdstr::findRemovableVariables {variables initNode actionNodes nextNode invariantNodes propertyNodes} {
    set usage {}
    foreach variable $variables {
        dict set usage $variable none
    }

    ::tdstr::accumulateVariableUsage $initNode $variables {} 0 usage
    foreach actionNode $actionNodes {
        ::tdstr::accumulateVariableUsage [::tdstr::namedBodyBody $actionNode] $variables {} 1 usage
    }
    ::tdstr::accumulateVariableUsage $nextNode $variables {} 0 usage
    foreach invariantNode $invariantNodes {
        ::tdstr::accumulateVariableUsage [::tdstr::namedBodyBody $invariantNode] $variables {} 0 usage
    }
    foreach propertyNode $propertyNodes {
        ::tdstr::accumulateVariableUsage [::tdstr::namedBodyBody $propertyNode] $variables {} 0 usage
    }

    set removable {}
    foreach variable $variables {
        if {[dict get $usage $variable] eq "frame"} {
            lappend removable $variable
        }
    }
    return $removable
}

proc ::tdstr::accumulateVariableUsage {node variables boundVariables conjunctive usageVar} {
    upvar 1 $usageVar usage
    set kind [lindex $node 0]

    if {$kind ne "object"} {
        return
    }

    if {[::tdstr::isFrameEqualityNode $node $variables $boundVariables] && $conjunctive} {
        set variable [::tdstr::frameEqualityVariable $node]
        if {[dict get $usage $variable] ne "real"} {
            dict set usage $variable frame
        }
        return
    }

    if {[::tdstr::isVarNode $node]} {
        set variable [::tdstr::nodeVariableName $node]
        if {[lsearch -exact $variables $variable] >= 0 && [lsearch -exact $boundVariables $variable] < 0} {
            dict set usage $variable real
        }
        return
    }
    if {[::tdstr::isNextNode $node]} {
        set variable [::tdstr::nodeVariableName $node]
        if {[lsearch -exact $variables $variable] >= 0 && [lsearch -exact $boundVariables $variable] < 0} {
            dict set usage $variable real
        }
        return
    }

    foreach pair [lrange $node 1 end] {
        set field [lindex $pair 0]
        set value [lindex $pair 1]

        if {$field eq "and"} {
            foreach child [::tdstr::arrayNodeItems $value] {
                ::tdstr::accumulateVariableUsage $child $variables $boundVariables $conjunctive usage
            }
            continue
        }

        if {$field eq "forall" || $field eq "exists"} {
            set quantifierVar [::tdstr::jsonStringValue [::tdstr::objectField $value "var"]]
            ::tdstr::accumulateVariableUsage [::tdstr::objectField $value "in"] $variables $boundVariables 0 usage
            ::tdstr::accumulateVariableUsage [::tdstr::objectField $value "body"] $variables [concat $boundVariables [list $quantifierVar]] 0 usage
            continue
        }

        if {[::tdstr::isArrayNode $value]} {
            foreach child [::tdstr::arrayNodeItems $value] {
                ::tdstr::accumulateVariableUsage $child $variables $boundVariables 0 usage
            }
            continue
        }

        if {[lindex $value 0] eq "object"} {
            ::tdstr::accumulateVariableUsage $value $variables $boundVariables 0 usage
        }
    }
}

proc ::tdstr::stripRemovableVariablesFromNamedBodies {namedBodies removableVariables} {
    set result {}
    foreach namedBody $namedBodies {
        lappend result [::tdstr::namedBodyNode [::tdstr::namedBodyName $namedBody] [::tdstr::stripRemovableVariables [::tdstr::namedBodyBody $namedBody] $removableVariables 1]]
    }
    return $result
}

proc ::tdstr::stripRemovableVariables {node removableVariables conjunctive} {
    if {[::tdstr::isFrameEqualityNode $node {} {}] && $conjunctive} {
        set variable [::tdstr::frameEqualityVariable $node]
        if {[lsearch -exact $removableVariables $variable] >= 0} {
            return "__omit__"
        }
    }

    set kind [lindex $node 0]
    if {$kind ne "object"} {
        return $node
    }

    set rebuiltPairs {}
    foreach pair [lrange $node 1 end] {
        set field [lindex $pair 0]
        set value [lindex $pair 1]

        if {$field eq "and"} {
            set children {}
            foreach child [::tdstr::arrayNodeItems $value] {
                set rewritten [::tdstr::stripRemovableVariables $child $removableVariables $conjunctive]
                if {$rewritten eq "__omit__"} {
                    continue
                }
                lappend children $rewritten
            }
            if {[llength $children] == 0} {
                return [::tdstr::trueNode]
            }
            if {[llength $children] == 1} {
                return [lindex $children 0]
            }
            lappend rebuiltPairs [list and [::tdstr::jsonArrayNode $children]]
            continue
        }

        if {$field eq "forall" || $field eq "exists"} {
            set payload [list object \
                [list var [::tdstr::objectField $value "var"]] \
                [list in [::tdstr::stripRemovableVariables [::tdstr::objectField $value "in"] $removableVariables 0]] \
                [list body [::tdstr::stripRemovableVariables [::tdstr::objectField $value "body"] $removableVariables 0]]]
            lappend rebuiltPairs [list $field $payload]
            continue
        }

        if {[::tdstr::isArrayNode $value]} {
            set rewrittenItems {}
            foreach child [::tdstr::arrayNodeItems $value] {
                set rewritten [::tdstr::stripRemovableVariables $child $removableVariables 0]
                if {$rewritten eq "__omit__"} {
                    error "Internal error: removable frame clause escaped conjunctive context"
                }
                lappend rewrittenItems $rewritten
            }
            lappend rebuiltPairs [list $field [::tdstr::jsonArrayNode $rewrittenItems]]
            continue
        }

        if {[lindex $value 0] eq "object"} {
            set rewritten [::tdstr::stripRemovableVariables $value $removableVariables 0]
            if {$rewritten eq "__omit__"} {
                error "Internal error: removable frame clause escaped conjunctive context"
            }
            lappend rebuiltPairs [list $field $rewritten]
            continue
        }

        lappend rebuiltPairs $pair
    }

    return [list object {*}$rebuiltPairs]
}

proc ::tdstr::trueNode {} {
    return [list object [list lit [::tdstr::jsonBoolean 1]]]
}

proc ::tdstr::namedBodyName {namedBody} {
    return [::tdstr::jsonStringValue [::tdstr::objectField $namedBody "name"]]
}

proc ::tdstr::namedBodyBody {namedBody} {
    return [::tdstr::objectField $namedBody "body"]
}

proc ::tdstr::objectField {node fieldName} {
    foreach pair [lrange $node 1 end] {
        if {[lindex $pair 0] eq $fieldName} {
            return [lindex $pair 1]
        }
    }
    error "Missing object field $fieldName"
}

proc ::tdstr::jsonStringValue {node} {
    if {[lindex $node 0] ne "string"} {
        error "Expected JSON string node, got $node"
    }
    return [lindex $node 1]
}

proc ::tdstr::isArrayNode {node} {
    return [expr {[llength $node] > 0 && [lindex $node 0] eq "array"}]
}

proc ::tdstr::arrayNodeItems {node} {
    return [lrange $node 1 end]
}

proc ::tdstr::isVarNode {node} {
    return [expr {[lindex $node 0] eq "object" && [llength $node] == 2 && [lindex [lindex $node 1] 0] eq "var"}]
}

proc ::tdstr::isNextNode {node} {
    return [expr {[lindex $node 0] eq "object" && [llength $node] == 2 && [lindex [lindex $node 1] 0] eq "next"}]
}

proc ::tdstr::nodeVariableName {node} {
    return [::tdstr::jsonStringValue [lindex [lindex $node 1] 1]]
}

proc ::tdstr::isFrameEqualityNode {node variables boundVariables} {
    if {[lindex $node 0] ne "object" || [llength $node] != 2} {
        return 0
    }
    set pair [lindex $node 1]
    if {[lindex $pair 0] ne "="} {
        return 0
    }
    set args [::tdstr::arrayNodeItems [lindex $pair 1]]
    if {[llength $args] != 2} {
        return 0
    }
    set left [lindex $args 0]
    set right [lindex $args 1]

    if {[::tdstr::isMatchingFramePair $left $right]} {
        set variable [::tdstr::nodeVariableName $right]
    } elseif {[::tdstr::isMatchingFramePair $right $left]} {
        set variable [::tdstr::nodeVariableName $left]
    } else {
        return 0
    }

    if {[llength $variables] > 0 && [lsearch -exact $variables $variable] < 0} {
        return 0
    }
    if {[llength $boundVariables] > 0 && [lsearch -exact $boundVariables $variable] >= 0} {
        return 0
    }
    return 1
}

proc ::tdstr::isMatchingFramePair {candidateNext candidateNow} {
    return [expr {[::tdstr::isNextNode $candidateNext]
            && [::tdstr::isVarNode $candidateNow]
            && [::tdstr::nodeVariableName $candidateNext] eq [::tdstr::nodeVariableName $candidateNow]}]
}

proc ::tdstr::frameEqualityVariable {node} {
    set args [::tdstr::arrayNodeItems [lindex [lindex $node 1] 1]]
    if {[::tdstr::isMatchingFramePair [lindex $args 0] [lindex $args 1]]} {
        return [::tdstr::nodeVariableName [lindex $args 0]]
    }
    return [::tdstr::nodeVariableName [lindex $args 1]]
}

proc ::tdstr::jsonString {value} {
    return [list string $value]
}

proc ::tdstr::jsonNumber {value} {
    return [list number $value]
}

proc ::tdstr::jsonBoolean {value} {
    return [list boolean [expr {$value ? "true" : "false"}]]
}

proc ::tdstr::jsonArrayNode {items} {
    set result [list array]
    foreach item $items {
        lappend result $item
    }
    return $result
}

proc ::tdstr::jsonArrayFromStrings {values} {
    set nodes {}
    foreach value $values {
        lappend nodes [::tdstr::jsonString $value]
    }
    return [::tdstr::jsonArrayNode $nodes]
}

proc ::tdstr::jsonObject {pairs} {
    return [list object {*}$pairs]
}

proc ::tdstr::literalNode {value quotedLiteral} {
    if {!$quotedLiteral} {
        set maybe [::tdstr::maybeLiteralNode $value]
        if {$maybe ne ""} {
            return $maybe
        }
    }
    return [::tdstr::jsonString [::tdstr::dslName $value]]
}

proc ::tdstr::writeJson {node indent} {
    set kind [lindex $node 0]
    if {$kind eq "string"} {
        return [::tdstr::writeJsonString [lindex $node 1]]
    }
    if {$kind eq "number"} {
        return [lindex $node 1]
    }
    if {$kind eq "boolean"} {
        return [lindex $node 1]
    }
    if {$kind eq "array"} {
        return [::tdstr::writeJsonArray [lrange $node 1 end] $indent]
    }
    if {$kind eq "object"} {
        return [::tdstr::writeJsonObject [lrange $node 1 end] $indent]
    }
    error "Cannot serialize unknown JSON node kind $kind"
}

proc ::tdstr::writeJsonObject {pairs indent} {
    if {[llength $pairs] == 0} {
        return "{}"
    }

    set pieces [list "\{"]
    set first 1
    foreach pair $pairs {
        if {!$first} {
            lappend pieces ","
        }
        set first 0
        lappend pieces "\n"
        lappend pieces [string repeat " " [expr {$indent + 2}]]
        lappend pieces [::tdstr::writeJsonString [lindex $pair 0]]
        lappend pieces ": "
        lappend pieces [::tdstr::writeJson [lindex $pair 1] [expr {$indent + 2}]]
    }
    lappend pieces "\n"
    lappend pieces [string repeat " " $indent]
    lappend pieces "\}"
    return [join $pieces ""]
}

proc ::tdstr::writeJsonArray {items indent} {
    if {[llength $items] == 0} {
        return "\[\]"
    }

    set pieces [list "\["]
    set first 1
    foreach item $items {
        if {!$first} {
            lappend pieces ","
        }
        set first 0
        lappend pieces "\n"
        lappend pieces [string repeat " " [expr {$indent + 2}]]
        lappend pieces [::tdstr::writeJson $item [expr {$indent + 2}]]
    }
    lappend pieces "\n"
    lappend pieces [string repeat " " $indent]
    lappend pieces "\]"
    return [join $pieces ""]
}

proc ::tdstr::writeJsonString {value} {
    set escaped [string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"] $value]
    return "\"$escaped\""
}

proc ::tdstr::dslName {thing} {
    return [string tolower $thing]
}

proc ::tdstr::plusSuffixedNameP {name} {
    return [expr {[string length $name] > 1 && [string index $name end] eq "+"}]
}

proc ::tdstr::looksLikeExprList {form} {
    if {[llength $form] <= 1} {
        return 0
    }
    set head [::tdstr::dslName [lindex $form 0]]
    return [expr {[lsearch -exact {quote set not eventually if assign equals unchanged* forall exists and or alternate-scenarios + - * / = != < <= > >= in implies} $head] >= 0}]
}

proc ::tdstr::isImplicitAndBlock {form} {
    if {[llength $form] <= 1} {
        return 0
    }
    if {[::tdstr::looksLikeExprList $form]} {
        return 0
    }
    foreach item $form {
        if {[llength $item] == 0} {
            return 0
        }
    }
    return 1
}

::tdstr::main
