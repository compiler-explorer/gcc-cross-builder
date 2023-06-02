#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (c) 2022, Compiler Explorer Authors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

import glob
from os.path import join, abspath, exists
import io
import re
from collections import defaultdict
import json

import argparse

LANGS=[ "ADA", "D", "FORTRAN", "CXX", "GO", "C", "OBJC", "OBJCXX" ]

CT_LANGS = {
    "ADA": "ADA",
    "D": "D",
    "FORTRAN": "FORTRAN",
    "CXX": "CXX",
    "GO": "GOLANG",
    "C" : "C",
    "OBJC" : "OBJC",
    "OBJCXX" : "OBJCXX",
}

parser = argparse.ArgumentParser(description='Update and check config files.')
parser.add_argument ('-a', '--arch', required=True, metavar="ARCH")
parser.add_argument ('-l', '--lang', help="Only handle LANG instead of trying them all",  required=False, metavar="LANG")
parser.add_argument ('--inplace', default=False, action='store_true', help='write change inplace')
parser.add_argument ('--output', required=False, metavar="OUTPUT")
parser.add_argument ('--error-if-missing-previous', action='store_true')
parser.add_argument ('--version', required=True, metavar="VERSION")
parser.add_argument ('--guess-previous', required=False, action='store_true')
parser.add_argument ('--previous-version', required=False, action='append', metavar="PREVVERSION")
parser.add_argument ('--config', required=False, metavar="CONFIG")
parser.add_argument ('--config-dir', required=False, metavar="CONFIGDIR")
parser.add_argument ('--config-todo', required=False, metavar="TODO_PATH")
parser.add_argument ('--summary', required=False, metavar="SUMMARY_PATH")

parser.add_argument ('--create-api-tests', required=False, metavar="TESTS_PATH")
parser.add_argument ('--api-test-host', default="http://localhost:10240", metavar="TEST_HOST")

PREVIOUS_VERSIONS = defaultdict(None)
PREVIOUS_VERSIONS.default_factory = lambda: None

PROP_RE = re.compile(r'[^#]*=.*')
COMPILERS_LIST_RE = re.compile(r'compilers=(.*)')
COMPILER_EXE_RE = re.compile(r'compiler\.(.*?)\.exe=(.*)')
COMPILER_ANYPROP_RE = re.compile(r'compiler\.(?P<name>.*?)\.(?P<prop>.*)=(?P<value>.*)')

API_TESTS_OUTPUT = None

TEST_FOR_LANG = {
    "C": "int f(void){return 0;} int main (){return f();}",
    "ADA": """procedure Example is
begin
null;
end Example;""",
    "D": """
    int square(int num) {
    return num * num;
}
    """,
    "GO": """
package main

func Square(x int) int {
    return x * x
}

func main() {}
    """,
    "CXX": "int f(void){return 0;} int main (){return f();}",
    "FORTRAN": """
program main
    implicit none
    integer :: i
    i = 3
end program
    """,
    "OBJC": "int f(void){return 0;} int main (){return f();}",
    "OBJCXX": "int f(void){return 0;} int main (){return f();}",
}

def create_test (arch, lang, compilerId):
    print(f"lang is {lang}")
    json_content = {
        "source" : TEST_FOR_LANG[lang],
        "options": {
            "userArguments": "-O0",
            "compilerOptions": {
                "skipAsm": False,
                "executorRequest": False
            },
            "filters": {
                "commentOnly": True,
                "demangle": True,
                "directives": True,
                "execute": False,
                "intel": True,
                "labels": True,
                "libraryCode": False,
                "trim": False
            }
        }
    }

    curl_cmd = f'''if curl -s "$CEHOST/api/compiler/{compilerId}/compile" --header "Accept: application/json"\\
       -X POST -H"Content-Type: application/json"\\
       -d\'{json.dumps(json_content)}\' |\\
    '''
    curl_cmd_end='''
    jq ".code" |\\
    grep -q 0
    then
      printf "%s [OK]\\n" "${line:${#NAME}}" >> test.result;
    else
      printf "%s [FAIL]\\n" "${line:${#NAME}}" >> test.result;
    fi
    '''

    API_TESTS_OUTPUT.write(f"NAME='{arch} {lang} {compilerId} ASM'\n")
    API_TESTS_OUTPUT.write(f'## Test for {compilerId}, {lang}/{arch} ASM only\n')
    API_TESTS_OUTPUT.write(f'echo -n "$NAME" >> test.result\n')
    API_TESTS_OUTPUT.write(curl_cmd)
    API_TESTS_OUTPUT.write(curl_cmd_end)

    API_TESTS_OUTPUT.write(f'## Test for {compilerId}, {lang}/{arch} ASM + BINARY\n')
    API_TESTS_OUTPUT.write(f"NAME='{arch} {lang} {compilerId} ASM+BINARY'\n")
    API_TESTS_OUTPUT.write(f'echo -n "$NAME" >> test.result\n')

    curl_test_bin = f'''if curl -s "$CEHOST/api/compilers?fields=id,supportsBinary" --header "Accept: application/json" |\\
    jq '.[] | select(.id=="{compilerId}") | .supportsBinary'|\\
    '''
    curl_test_bin_end='''
    grep -q false
    then
      printf "%s [SKIPPED (not supported)]\n" "${line:${#NAME}}" >> test.result;
    else
    '''

    API_TESTS_OUTPUT.write(curl_test_bin)
    API_TESTS_OUTPUT.write(curl_test_bin_end)
    json_content["options"]["filters"]['binary'] = True
    API_TESTS_OUTPUT.write(curl_cmd)
    API_TESTS_OUTPUT.write(curl_cmd_end)
    API_TESTS_OUTPUT.write('\nfi\n')

class Line:
    def __init__(self, line_number, text):
        self.number = line_number
        self.text = text.strip()

    def __str__(self):
        return f'<{self.number}> {self.text}'

def match_and_add(line: Line, expr, s):
    match = expr.match(line.text)
    if match:
        s[match.group(1)]=line
    return match

def match_and_update(line: Line, expr, s, split=':'):
    match = expr.match(line.text)
    if match:
        s.update(match.group(1).split(split))
    return match

def parse_file(file: str):
    listed_compilers = {}
    compilers_exe = {}
    last_compilers_prop = {}
    compilers_name_prop = {}

    with open(file) as f:
        for line_number, text in enumerate(f, start=1):
            text = text.strip()
            if not text:
                continue
            line = Line(line_number, text)

            match_prop = PROP_RE.match(line.text)
            if not match_prop:
                continue

            match_compilers = COMPILERS_LIST_RE.search(line.text)
            if match_compilers:
                ids = match_compilers.group(1).split(':')
                for elem_id in ids:
                    if elem_id.startswith('&'):
                        pass
                    elif '@' not in elem_id:
                        listed_compilers[elem_id] = line

            m = match_and_add(line, COMPILER_EXE_RE, compilers_exe)

            m = COMPILER_ANYPROP_RE.match(line.text)
            if m:
                last_compilers_prop[m.group('name')]=line
                if m.group('prop') == 'name':
                    compilers_name_prop[m.group('name')]=m.group('value')

            m = match_and_add(line, COMPILER_ANYPROP_RE, last_compilers_prop)
    return {
        'listed_compilers': listed_compilers,
        'compilers_exe': compilers_exe,
        'last_compilers_prop': last_compilers_prop,
        'compilers_name_prop': compilers_name_prop,
    }

# because some arch (ie. riscv) are using a nicer naming {arch}-bla. But we
# don't want to change all the others... So special casing here.
COMPILER_ID_PATTERN = defaultdict(None)
COMPILER_ID_PATTERN.default_factory = lambda: {
    'D': 'gdc{arch}{version}',
    'ADA': 'gnat{arch}{version}',
    'C': 'c{arch}g{version}',
    'CXX': '{arch}g{version}',
    'FORTRAN': 'f{arch}g{version}',
    'GO': 'gccgo{arch}{version}',
    'OBJC': 'objc{arch}g{version}',
    'OBJCXX': 'objcpp{arch}g{version}',
}

COMPILER_ID_PATTERN['riscv64'] = {
    'D': 'gdc{arch}{version}',
    'ADA': 'gnat{arch}{version}',
    'C': 'rv64-cgcc{version}',
    'CXX': 'rv64-gcc{version}',
    'FORTRAN': 'f{arch}g{version}',
    'GO': 'gccgo{arch}{version}',
    'OBJC': 'objcrv32g{version}',
    'OBJCXX': 'objcppgccrv64{version}',
}

COMPILER_ID_PATTERN['riscv32'] = {
    'D': 'gdc{arch}{version}',
    'ADA': 'gnat{arch}{version}',
    'C': 'rv32-cgcc{version}',
    'CXX': 'rv32-gcc{version}',
    'FORTRAN': 'f{arch}g{version}',
    'GO': 'gccgo{arch}{version}',
    'OBJC': 'objcrv32g{version}',
    'OBJCXX': 'objcppgccrv32{version}',
}

ARCH_RENAMING_IN_CONFIG={
    "powerpc": "ppc",
    "powerpc64": "ppc64",
    "powerpc64le": "ppc64le",
    "riscv32": "riscv",
    "sparc-leon": "sparcleon",
}

FILEPREFIX = {
    'D': 'd',
    'ADA': 'ada',
    'C': 'c',
    'CXX': 'c++',
    'FORTRAN': 'fortran',
    'GO': 'go',
    'OBJC': 'objc',
    'OBJCXX': 'objc++',
}

COMPILER_SUFFIX = {
    'D': 'gdc',
    'ADA': 'gnatmake',
    'C': 'gcc',
    'CXX': 'g++',
    'FORTRAN': 'gfortran',
    'GO': 'gccgo',
    'OBJC': 'gcc',
    'OBJCXX': 'g++',
}

class Woops(Exception):
    pass

class AlreadyDefined(Exception):
    pass

class ManualFixupNeeded(Exception):
    pass

class Fixup:
    def __init__(self, line_number, text, action):
        self.line = line_number
        self.text = text
        self.action = action

    def __repr__(self):
        action=f"NONE{self.action}"
        match self.action:
            case 1:
                action="replacing it with"
            case 2:
                action="adding after newline"
            case 3:
                action="appending after"

        return f'Fixup line {self.line} by {action} text: {self.text}'

def generateConfig (arch: str, lang: str, version: str, directory: str, name):
    objdump_path = findFile(arch, lang, version, directory, "objdump")
    cppfilt_path = findFile(arch, lang, version, directory, "c++filt")
    compiler_path = findCompiler(arch, lang, version, directory)
    compiler_id = CompilerId(arch, version, lang)
    ret = f"""
compiler.{compiler_id}.exe={compiler_path}
compiler.{compiler_id}.semver={version}
compiler.{compiler_id}.objdumper={objdump_path}
compiler.{compiler_id}.demangler={cppfilt_path}
"""
    ## This is only needed when the "groupname semver" is not applicable, which we should have everywhere.
    if name != None:
        ret += f"compiler.{compiler_id}.name={name}\n"
    return ret

def findFile (arch: str, lang: str, version: str, directory: str, suffix: str):
    target_dir='{directory}/{arch}/gcc-{version}/**/*-{suffix}'.format(directory=directory, arch=arch, version=version, suffix=suffix)
    print("search in {}".format(target_dir))
    for f in glob.glob(target_dir, recursive=True):
        return abspath(f)
    raise Woops("Can't find '{target_dir}, something's wrong")

def findCompiler (arch: str, lang: str, version: str, directory: str):
    return findFile(arch, lang, version, directory, COMPILER_SUFFIX[lang])

def CompilerId (arch: str, version: str, lang: str):
    renamed_arch = arch
    if arch in ARCH_RENAMING_IN_CONFIG:
        renamed_arch = ARCH_RENAMING_IN_CONFIG[arch]

    return COMPILER_ID_PATTERN[arch][lang].format(arch=renamed_arch, version=version.replace('.', ''))

def Do(args, lang):
    new_compiler_id = CompilerId(args.arch, args.version, lang)

    try:
        Wrapped_Do(args, lang)
        if API_TESTS_OUTPUT:
            create_test(args.arch, lang, new_compiler_id)

    except ManualFixupNeeded as e:
        if API_TESTS_OUTPUT:
            create_test(args.arch, lang, new_compiler_id)
        raise e
    except AlreadyDefined as e:
        if API_TESTS_OUTPUT:
            create_test(args.arch, lang, new_compiler_id)
        raise e

## Used for creating fake tests at the end.
NEW_COMPILERS = {}

def Wrapped_Do(args, lang: str):
    fixups = defaultdict(list)

    if args.config:
        conf = args.config
    else:
        conf = join(args.config_dir, "{lang}.amazon.properties".format(lang=FILEPREFIX[lang]))

    p = parse_file(conf)
    parse_previous_version(args.version, args.arch, lang, args.guess_previous, p)

    new_compiler_id = CompilerId(args.arch, args.version, lang)

    NEW_COMPILERS[new_compiler_id] = {
        'arch' : args.arch,
        'version': args.version,
        'lang': lang,
    }

    previous_compiler_id = None

    if get_previous_version(args.arch, lang):
        previous_compiler_id = CompilerId(args.arch, get_previous_version(args.arch, lang), lang)

    print(new_compiler_id)

    if new_compiler_id in p['listed_compilers']:
        msg = "{compiler} is already in {conf} at line {line}".format(
            compiler=new_compiler_id,
            conf=conf,
            line=p['listed_compilers'][new_compiler_id].number)

        raise AlreadyDefined(msg)
    else:
        print ("{compiler} not in {conf}".format(compiler=new_compiler_id, conf=conf))
        #findCompiler (args.arch, lang, args.version, '/opt/compiler-explorer')

        if previous_compiler_id not in p['listed_compilers']:
            msg = "Could not find previous compiler version {version}".format(version=get_previous_version(args.arch, lang))

            if args.error_if_missing_previous:
                raise Woops(msg)
            else:
                print (msg)

            config_fixup = generateConfig(args.arch, lang, args.version, '/opt/compiler-explorer', None)
            todo_msg = f'\nPlease add the following in {conf}:\n8<---8<--- BEGIN ---8<---8<---\n{config_fixup}\n8<---8<--- END ---8<---8<---\n'

            if args.config_todo:
                with open(args.config_todo, 'a') as todo_f:
                    todo_f.write (todo_msg)
            else:
                print(todo_msg)

            raise ManualFixupNeeded()
        else:
            previous_listed_line = p['listed_compilers'][previous_compiler_id]
            if not previous_listed_line:
                msg = f"Error, can't find where previous compiler {previous_compiler_id} is listed"
                raise Woops(msg)

            fixups[previous_listed_line.number].append(Fixup(
                previous_listed_line.number,
                f':{new_compiler_id}',
                3))

            last_line = p['last_compilers_prop'][previous_compiler_id].number
            print ("Last prop set for previous {version} at line {line}".format(
                version=get_previous_version(args.arch, lang),
                line=last_line))

            if previous_compiler_id in p['compilers_name_prop']:
                ## replace previous version by new version, and try to handle case of version M.m.p with name omiting .p
                name = p['compilers_name_prop'][previous_compiler_id]
                name = name.replace(get_previous_version(args.arch, lang), args.version)
                name = name.replace(get_previous_version(args.arch, lang)[0:-2], args.version[0:-2])
            else:
                name = None
            fixups[last_line].append(Fixup(
                last_line,
                generateConfig(args.arch, lang, args.version, '/opt/compiler-explorer', name),
                2))

    output = io.StringIO()
    with open(conf) as f:
        for line_number, text in enumerate(f, start=1):
            if line_number in fixups:
                for fixup in fixups[line_number]:
                    match fixup.action:
                        case 1:
                            print (fixup.text, file=output, end="")
                        case 2:
                            print (text, file=output, end="")
                            print (fixup.text, file=output, end="")
                        case 3:
                            print (text.strip() + fixup.text, file=output)
            else:
                print (text, file=output, end="")
        # output.close()

    if args.inplace:
        output_path = conf
    else:
        output_path = args.output

    with open(output_path, "w") as f:
        f.write(output.getvalue())

def get_previous_version (lang, arch):
    l_a = f'{lang};{arch}'.format(lang, arch).upper()

    if l_a in PREVIOUS_VERSIONS:
        return PREVIOUS_VERSIONS[l_a]

    return PREVIOUS_VERSIONS[lang]

def test_prev(version, arch, lang, parsed_conf):
    version = version.split('.')

    for major in reversed(range(5, int(version[0])+1)):
        for minor in reversed(range(1,10)):

            test_cid = CompilerId (arch, f"{major}.{minor}", lang)
            ## print(f"Testing {major}.{minor}: {test_cid}")
            if test_cid in parsed_conf['listed_compilers']:
                conf_found = parsed_conf['listed_compilers'][test_cid]
                print(f"FOUND {test_cid} in line '{conf_found.text}' at line {conf_found.number}")
                return (f"{arch};{lang}".upper(), f"{major}.{minor}")

            for patch in reversed(range(0,10)):
                test_cid = CompilerId (arch, f"{major}.{minor}.{patch}", lang)
                ## print(f"Testing {major}.{minor}.{patch}: {test_cid}")
                if test_cid in parsed_conf['listed_compilers']:
                    conf_found = parsed_conf['listed_compilers'][test_cid]
                    print(f"FOUND {test_cid} in line '{conf_found.text}' at line {conf_found.number}")
                    return (f"{arch};{lang}".upper(), f"{major}.{minor}.{patch}")
    print(f"Did not find any previous compiler for {arch} {lang}")
    return None

def parse_previous_version(version, arch, lang, guess_previous, parsed_conf):

    if guess_previous:
        guessed = test_prev(version, arch, lang, parsed_conf)
        if guessed:
            PREVIOUS_VERSIONS[guessed[0]] = guessed[1]

    if args.previous_version:
        for pv in args.previous_version:
            pv_s = pv.split(':')
            if len(pv_s) == 1:
                PREVIOUS_VERSIONS.default_factory = lambda: pv_s[0]
            elif len(pv_s) == 2:
                PREVIOUS_VERSIONS[pv_s[0].upper()] = pv_s[1]

def check_lang_enabled_in_ctng (args, lang):

    ## You can't disable C \_o<
    if lang == "C":
        return True

    ct_ng_config = join("build", "latest", f"{args.arch}-{args.version}.config")


    ct_lang = CT_LANGS[lang]
    print(f"check for CT_CC_LANG_{ct_lang} in {ct_ng_config}")

    with open(ct_ng_config) as ctng_conf:
        for line in ctng_conf:
            if re.match(f"^CT_CC_LANG_{ct_lang}=y", line):
                return True
    return False

if __name__ == '__main__':
    args = parser.parse_args()

    if args.create_api_tests:
        results_exists = exists(args.create_api_tests)

        API_TESTS_OUTPUT = open(args.create_api_tests, "a")

        if not results_exists:
            API_TESTS_OUTPUT.write('#!/bin/bash\n')
            API_TESTS_OUTPUT.write('set -euo pipefail\n')
            API_TESTS_OUTPUT.write("line='----------------------------------------'\n")
            API_TESTS_OUTPUT.write(f"CEHOST='{args.api_test_host}'\n")

    if args.lang:
        Do(args, args.lang)
    else:
        for lang in LANGS:
            if check_lang_enabled_in_ctng (args, lang):
                try:
                    Do(args, lang)
                    if args.summary:
                        with open(args.summary, "a") as f:
                            f.write(f"OK: {args.arch} {args.version} {lang}\n")

                except ManualFixupNeeded:
                    msg = f"MANUAL FIXUP NEEDED: {args.arch} {args.version} {lang}"
                    if args.summary:
                        with open(args.summary, "a") as f:
                            f.write(f"{msg}\n")
                    else:
                        print(msg)

                except AlreadyDefined:
                    msg = f"ALREADY EXISTS: {args.arch} {args.version} {lang}"
                    if args.summary:
                        with open(args.summary, "a") as f:
                            f.write(f"{msg}\n")
                    else:
                        print(msg)

                except Woops as err:
                    if args.summary:
                        with open(args.summary, "a") as f:
                            f.write(f"NOT OK (ERROR): {args.arch} {args.version} {lang}\n")
                    else:
                        raise err

        ## Create some fake test that checks the test harness can fail. All
        ## tests created here are supposed to FAIL.
        if args.create_api_tests:
            API_TESTS_OUTPUT.write("## Fake tests, they should all FAIL.\n")
            API_TESTS_OUTPUT.write("echo -e '\\n\\n#### Fake tests, they should FAIL or be SKIPPED, but never PASS\\n' >> test.result\n")
            first_cid = list(NEW_COMPILERS.keys())[0]
            compiler = NEW_COMPILERS[first_cid]
            lang = None

            for l in LANGS:
                if l != compiler['lang'] and not (l in ["C", "CXX"] and compiler['lang'] in ["C", "Cxx"]):
                    lang = l
                    break

            ## Mismatching lang input
            create_test(compiler['arch'], lang, first_cid)
            API_TESTS_OUTPUT.write("## End of fake tests.\n")
            API_TESTS_OUTPUT.write("echo -e '#### End of fake tests\\n' >> test.result\n")
