MATLAB Data Serialization
=========================

Functions `mxencode` and `mxdecode` implement efficient serialize/deserialize
operations using a binary format for all basic MATLAB data types: numeric,
complex, logical, char, cell, struct, sparse, or any combination thereof.

These functions may be used directly from MATLAB without any additional
toolboxes or be converted to standalone C/C++ code with MATLAB Coder to simplify
data exchange between MATLAB and non-MATLAB components. See `mxcgentest.m` and
`mxcgenfunc.m` for an example.

Run `help mxencode` and `help mxdecode` in MATLAB for more info (or read the top
comment in each file).
