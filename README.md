# Utility for sending files to Skatteverket

This can be used for converting files from your accounting-software to files that can be uploaded to Skatteverket.

Everything is written in Swift, so it requires you to have Swift installed.

## SIEtoSRU.swift

This can be used for converting SIE-files (that you can usually export from your accounting-software) to SRU-files (which should uploaded alongside inkomstdeklaration 1).

```
./SIEtoSRU.swift <path-to-your-SIE>.se <postnr> <postort>
```

Postnr and postort must be set manually, since they aren't present in the SIE-files, but are required in the SRU-files. Running the above will result in INFO.sru and BLANKETTER.sru, which can be uploaded to skatteverket.

This is only tested with very simple cases, so there are probably lots of cases that aren't covered.

## Disclaimers

This is just tested for my own purposes, with data exported from [http://bokio.io] you should always manually verify the files produced. Improvement PR:s and comments are welcome!
