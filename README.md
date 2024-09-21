### GCC Cross Compiler build scripts

The repository is part of the [Compiler Explorer](https://godbolt.org/) project. It builds
the docker images used to build the various GCC cross-compilers used on the site.

## How to add a new target

- create a ct-ng config:
  - can be based on a ct-ng sample
  - can be a new config
  - disable PROGRESS_BAR and any gdb features
- check it builds correctly:
  `./ct-ng build`
- copy the config in this repository in `build/latest` following the naming convention.
- use `local_build.sh` to test a build it within the docker container
  `./local_build.sh arm64 13.2.0`
- add ct-ng config and commit (and open a Pull Request)

Later, when the config is added, trigger a build:

``` sh
gh workflow run -R compiler-explorer/infra 'Custom compiler build' -f image=gcc-cross -f version="arm64 14.2.0"
```

Later, when the build is finished, add the needed config in `infra` repository. Test it with:

``` sh
 ./bin/ce_install install compilers/c++/cross/gcc/arm 14.2.0
```

When the compiler is installed, then you can update the config files using the
instructions below. The script won't touch any config as it's a new target, but
it will provide most of the content, ready to be copy/pasted all around.

## How to add a new version for some/all cross compilers

The script [check_and_update_conf.py](./check_and_update_conf.py) can be used to automate some work:
- update the various configurations for our nodes on AWS (i.e. all the
  `*.amazon.properties` in the
  [compiler-explorer](https://github.com/compiler-explorer/compiler-explorer/tree/main/etc/config)
  repository).
- while doing so, it checks the mapping between the languages enabled in the
  crosstool-ng config file and the actually installed compiler.
- generate a simple script to smoketest the newly added compilers using the
  [API](https://github.com/compiler-explorer/compiler-explorer/blob/main/docs/API.md)

Beware that you should not trust blindly everything the script does. You should
probably still try manually (or at least some random combination if testing
everything is too much).

The script is invoked for a given target arch and will do its magic from this point. Here's a sample execution for adding GCC 12.2.0 for ARM64:

```
$ ./check_and_update_conf.py -a arm64 --version 12.2.0\
   --guess-previous\
   --config-dir ~/git/compiler-explorer/compiler-explorer/etc/config/\
   --inplace \
   --config-todo fixups.txt \
   --summary summary.txt \
   --create-api-tests tests.sh
```

This will read/modify (`--inplace`) needed config files located in
`~/git/compiler-explorer/compiler-explorer/etc/config`. The script tries to be
smart and find a previous matching compiler for all languages for the target,
but this may not be possible (e.g. the naming pattern is different or there is
really no previous one). In this case, the script still produces some
configuration that you need to add manually. It in the `fixups.txt` (as
specified by `--config-todo fixups.txt`):

```
Please add the following in /bla/git/compiler-explorer/compiler-explorer/etc/config/c++.amazon.properties:
8<---8<--- BEGIN ---8<---8<---

compiler.rv32-cgcc1220.exe=/opt/compiler-explorer/riscv32/gcc-12.2.0/riscv32-unknown-linux-gnu/bin/riscv32-unknown-linux-gnu-g++
compiler.rv32-cgcc1220.semver=12.2.0
compiler.rv32-cgcc1220.objdumper=/opt/compiler-explorer/riscv32/gcc-12.2.0/riscv32-unknown-linux-gnu/bin/riscv32-unknown-linux-gnu-objdump
compiler.rv32-cgcc1220.demangler=/opt/compiler-explorer/riscv32/gcc-12.2.0/riscv32-unknown-linux-gnu/bin/riscv32-unknown-linux-gnu-c++filt
compiler.rv32-cgcc1220.name=riscv32 12.2.0

8<---8<--- END ---8<---8<---
```

The `--summary summary.txt ` instructs the script to create a small summary of what happened and what you still need to do by hand:

```
ALREADY EXISTS: riscv32 12.2.0 D
ALREADY EXISTS: riscv32 12.2.0 FORTRAN
MANUAL FIXUP NEEDED: riscv32 12.2.0 CXX
ALREADY EXISTS: riscv32 12.2.0 C
ALREADY EXISTS: riscv64 12.2.0 ADA
ALREADY EXISTS: riscv64 12.2.0 D
ALREADY EXISTS: riscv64 12.2.0 FORTRAN
MANUAL FIXUP NEEDED: riscv64 12.2.0 CXX
ALREADY EXISTS: riscv64 12.2.0 GO
ALREADY EXISTS: riscv64 12.2.0 C
ALREADY EXISTS: mipsel 12.2.0 D
ALREADY EXISTS: mipsel 12.2.0 FORTRAN
ALREADY EXISTS: mipsel 12.2.0 CXX
ALREADY EXISTS: mipsel 12.2.0 GO
ALREADY EXISTS: mipsel 12.2.0 C
ALREADY EXISTS: mips64el 12.2.0 FORTRAN
ALREADY EXISTS: mips64el 12.2.0 CXX
ALREADY EXISTS: mips64el 12.2.0 GO
ALREADY EXISTS: mips64el 12.2.0 C
```

It can also create a shell script (it has been `shellcheck`ed, but would not
qualify for best shell-style) to tests that all newly added compilers are
behaving. You still need to check if the results are expected as the script
can't really infer all prop values (in particular for binarySupports):
`--create-api-tests tests.sh --api-test-host http://localhost:10240`. The test
scripts also contains tests that are expected to FAIL in order to test the test
harness. These tests are clearly identified in the result file (`test.result`).

The test script doesn't take any argumuent:
```
$ bash tests.sh
```

And the `test.result` looks like:

```
mipsel D gdcmipsel1220 ASM-------------- [OK]
mipsel D gdcmipsel1220 ASM+BINARY------- [OK]
mipsel FORTRAN fmipselg1220 ASM--------- [OK]
mipsel FORTRAN fmipselg1220 ASM+BINARY-- [SKIPPED (not supported)]
mipsel CXX mipselg1220 ASM-------------- [OK]
mipsel CXX mipselg1220 ASM+BINARY------- [OK]
mipsel GO gccgomipsel1220 ASM----------- [OK]
mipsel GO gccgomipsel1220 ASM+BINARY---- [SKIPPED (not supported)]
mipsel C cmipselg1220 ASM--------------- [OK]
mipsel C cmipselg1220 ASM+BINARY-------- [OK]


#### Fake tests, they should FAIL or be SKIPPED, but never PASS

mipsel ADA gdcmipsel1220 ASM------------ [FAIL]
mipsel ADA gdcmipsel1220 ASM+BINARY----- [FAIL]
#### End of fake tests

mips64el FORTRAN fmips64elg1220 ASM----- [OK]
mips64el FORTRAN fmips64elg1220 ASM+BINARY [SKIPPED (not supported)]
mips64el CXX mips64elg1220 ASM---------- [OK]
mips64el CXX mips64elg1220 ASM+BINARY--- [OK]
mips64el GO gccgomips64el1220 ASM------- [OK]
```

When you need to update several targets at once, you can use the following
sample command. You currently need to clear some output files as they are
appended by the several invocations.

```
rm -f test.result tests.sh summary.txt test.result fixups.txt;\
  for i in arm arm64 avr mips mips64 msp430 powerpc powerpc64 powerpc64le s390x riscv32 riscv64 mipsel mips64el;
    do
      ./check_and_update_conf.py -a $i --version 12.2.0 --guess-previous \
         --config-dir ~/git/compiler-explorer/compiler-explorer/etc/config/\
         --inplace  --config-todo fixups.txt --summary summary.txt --create-api-tests tests.sh
    done
```



