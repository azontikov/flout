# FLOUT -- FLuka OUtput processing scripT

FLOUT is a shell script for processing FLUKA output binary files by
means of readout codes supplied with FLUKA package. The script requires
FLUKA package distributed by CERN or INFN and bash shell version >= 4.0.
FLOUT parses FLUKA input files in FIXED and FREE formats. It also treats
nested preprocessor directives.

User runs the script with the command (assume that flout is an alias for
flout.sh)
```
$ flout [mode] [file] -d [directory] [parameter 1] ... [parameter n]
```
where [mode] and [file] are mandatory arguments. All the rest arguments
are optional.

Auto mode [-a] parses FLUKA input file, finds all valid scoring cards
and processes binary data.

Interactive mode [-i] parses FLUKA input file, finds all valid scoring
cards and prompts whether to process data for this card or not.

Manual mode [-m] processes data according to text file supplied by the
user.

Scan mode [-s] generates text file for manual [-m] mode.

Optional flag [-d] is used to supply the path to destination directory
for produced results.

The help section is displayed by running
```
$ flout -h
```

By default FLOUT searches for FLUKA readout programs inside CERN FLUKA
which /bin folder should be available on the $PATH. Supplying the
[--old] parameter allows to search for readout codes inside INFN FLUKA
which requires $FLUPRO shell variable.

Optional parameters:

[--log] 	save output from FLUKA readout programs to text file

[--clean] 	move (rather that copy) results to [directory]

[--dat] 	convert USRBIN binary output to plain text

[--reuse] 	reprocessing of already processed binary data

[--old] 	use readout programs from old (INFN) FLUKA package

The script has the following limitations:
1. Do not use exponential notation for logical output unit in FLUKA
input file. For instance, use 23 or 23.0 rather than 0.23E+02 or
23000.0E-03
2. Do not --reuse USRYIELD data due to SIGFPE somewhere from
usysuw.f:924 and usysuw.f:1410

## Example usage

Example 1. Run example.inp, process all binary files in auto mode.
```
$ rfluka -N0 -M5 example.inp
$ flout -a example.inp
```

Example 2. Run example.inp, process data in interactive mode, copy it to
result subdirectory and save log.
```
$ rfluka -N0 -M5 example.inp
$ mkdir result
$ flout -i example.inp -d result/ --log
```

Example 3. Run example.inp, process unit 50 and unit 51 USRBIN data in
manual mode, convert USRBIN binary data to plain text, move it to result
subdirectory.
```
$ rfluka -N0 -M5 example.inp
$ mkdir result
$ cat example.txt
example
50 USRBIN
51 USRBIN
$ flout -m example.txt -d result/ --dat --clean
```

Example 4. Make copies of example.inp with different seeds and place
them into subdirectories. Run example_001.inp in subdirectory
example4_001, run example_002.inp in subdirectory example4_002, process
all binary files in auto mode and copy them into subdirectory result.
Reuse (merge) already processed data from example_001.inp and
example_002.inp.
```
$ cd example4_001
$ rfluka -N0 -M5 example_001.inp
$ flout -a example_001.inp -d ../result
$ cd ../example4_002
$ rfluka -N0 -M5 example_002.inp
$ flout -a example_002.inp -d ../result
$ cd ../result
$ flout -a ../example.inp --reuse
```

Example 5. Scan example.inp and generate example.txt file for manual
mode.
```
$ rfluka -N0 -M5 example.inp
$ flout -s example.inp
$ flout -m example.txt
```
