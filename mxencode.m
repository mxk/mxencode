%MXENCODE   Serialize data into a byte array.
%
%   BUF = MXENCODE(V) encodes V, which may be numeric (including complex),
%     logical, char, cell, struct, sparse, or any combination thereof, into a
%     uint8 column vector. Use MXDECODE to extract the original value from BUF.
%
%   BUF = MXENCODE(V,SIG) encodes the specified SIG into the buffer signature.
%     SIG must be an integer in the range [0,239] and may be used to provide
%     application-specific information about buffer contents. The default
%     value, used if SIG is unspecified or empty, is the answer to the ultimate
%     question of life, the universe, and everything.
%
%   BUF = MXENCODE(V,SIG,BYTEORDER) encodes V using the specified BYTEORDER,
%     which must be one of '', 'B', or 'L' for native, big-endian, or
%     little-endian, respectively. The default is native.
%
%   [BUF,ERR] = MXENCODE(V,SIG,BYTEORDER) activates standalone mode for
%     generating C/C++ code with MATLAB Coder. SIG and BYTEORDER arguments may
%     be omitted. If an error is encountered during encoding, ERR will contain
%     its message id and BUF will be empty.
%
%   MXENCODE and MXDECODE were designed for use with MATLAB Coder to provide an
%   efficient data exchange format between MATLAB and non-MATLAB code. Multiple
%   restrictions are placed on the encoded data when these functions are
%   compiled for standalone use. See MXDECODE for more info.
%
%   Buffer format version 240 (FIELD{#BYTES}): [ SIG{2} VALUE{1-N} PAD{1-4} ]
%
%   SIG is a uint16 value that allows the decoder to identify a valid buffer and
%   determine the byte order that was used for encoding. The low byte is the
%   user-specified value (42 by default). The high byte is the buffer format
%   version. It is incremented by one for all backward-incompatible changes to
%   the encoding format. The current version is 240. To support unambiguous byte
%   order detection, the low byte must be less than 240.
%
%   VALUE is a recursive encoding of V based on its class. The first byte is a
%   tag in which the lower 5 bits specify the class and the upper 3 bits specify
%   size encoding format as follows (value of tag shifted right by 5):
%     0 = scalar (1x1):                          [ TAG{1} DATA ]
%     1 = column vector (Mx1) with M < 256:      [ TAG{1} M{1} DATA ]
%     2 = row vector (1xN) with N < 256:         [ TAG{1} N{1} DATA ]
%     3 = matrix (MxN) with M < 256 and N < 256: [ TAG{1} M{1} N{1} DATA ]
%     4 = normalized empty value (0x0):          [ TAG{1} ]
%     5 = uint8 general format:  [ TAG{1} NDIMS{1} S1{1} S2{1} ... DATA ]
%     6 = uint16 general format: [ TAG{1} NDIMS{1} S1{2} S2{2} ... DATA ]
%     7 = uint32 general format: [ TAG{1} NDIMS{1} S1{4} S2{4} ... DATA ]
%
%   PAD contains 1-4 bytes all set to the bitwise complement of PAD length. It
%   serves as an explicit end-of-data marker and ensures that BUF contains a
%   multiple of 4 bytes.
%
%   Limits:
%     Maximum number of array dimensions: 255
%     Maximum number of array elements: 2,147,483,647
%     Maximum buffer size: 2,147,483,644
%
%   See also MXDECODE, TYPECAST, SWAPBYTES, COMPUTER.

%   Written by Maxim Khitrov (February 2017)

function [buf,err] = mxencode(v, sig, byteOrder)  %#codegen
	narginchk(1, 3);
	cgen = int32(nargout == 2);
	ctx = struct( ...
		'buf',  zeros(64, 1, 'uint8'), ...
		'len',  int32(0), ...
		'swap', false, ...
		'cgen', false(1 - cgen), ...  % Empty is compile-time true
		'err',  '' ...
	);
	if cgen
		coder.cstructname(ctx, 'MxEncCtx');
		coder.varsize('ctx.buf');
		coder.varsize('ctx.err', [1,32]);
	end

	% Define buffer signature
	bsig = bitshift(uint16(240),8) + 42;
	if nargin >= 2 && ~isempty(sig)
		if isscalar(sig) && uint16(sig) < 240
			bsig = bsig - 42 + uint16(sig);
		else
			ctx = fail(ctx, 'invalidSig');
		end
	end

	% Configure encoder byte order
	if nargin == 3 && ~isempty(byteOrder)
		if byteOrder == 'B' || byteOrder == 'L'
			native = char(bitand(typecast(uint8('LB'),'uint16'), 255));
			ctx.swap = (byteOrder ~= native);
		else
			ctx = fail(ctx, 'invalidByteOrder');
		end
	end

	% Encode signature, v, and padding
	ctx = append(ctx, bsig);
	ctx = encAny(ctx, v);
	pad = uint8(4 - bitand(ctx.len,3));
	ctx = appendBytes(ctx, repmat(bitcmp(pad),pad,1));
	err = ctx.err;
	if ~isempty(ctx.buf) && isempty(err)
		buf = ctx.buf(1:ctx.len);
	else
		buf = zeros(0, 1, 'uint8');
	end
end

function ctx = encAny(ctx, v)
	if isnumeric(v)
		ctx = encNumeric(ctx, v);
	elseif islogical(v)
		ctx = encLogical(ctx, v);
	elseif ischar(v)
		ctx = encChar(ctx, v);
	elseif iscell(v)
		ctx = encCell(ctx, v);
	elseif isstruct(v)
		ctx = encStruct(ctx, v);
	else
		ctx = fail(ctx, 'unsupported');
	end
end

function ctx = encNumeric(ctx, v)
	if issparse(v)
		ctx = encSparse(ctx, v);
	elseif isreal(v)
		ctx = encTag(ctx, v, class(v));
		ctx = append(ctx, v(:));
	else
		ctx = encTag(ctx, v, 'complex');
		ctx = encTag(ctx, 0, class(v));
		ctx = append(ctx, real(v(:)));
		ctx = append(ctx, imag(v(:)));
	end
end

function ctx = encLogical(ctx, v)
	if issparse(v)
		ctx = encSparse(ctx, v);
	else
		ctx = encTag(ctx, v, 'logical');
		ctx = appendBytes(ctx, uint8(v(:)));
	end
end

function ctx = encSparse(ctx, v)
	idx = find(v);
	if isempty(idx)
		idx = reshape(idx, 0, 0);
		cid = uint8(1);
	else
		cid = minUint(idx(end));
	end
	ctx = encTag(ctx, v, 'sparse');
	switch cid
	case 1
		ctx = encNumeric(ctx, uint8(idx));
	case 2
		ctx = encNumeric(ctx, uint16(idx));
	case 3
		ctx = encNumeric(ctx, uint32(idx));
	otherwise
		ctx = encNumeric(ctx, idx);  % Will fail
	end
	ctx = encAny(ctx, full(v(idx)));
end

function ctx = encChar(ctx, v)
	if all(v(:) <= intmax('uint8'))
		ctx = encTag(ctx, v, 'char8');
		ctx = appendBytes(ctx, uint8(v(:)));
	elseif ~ctx.cgen
		ctx = encTag(ctx, v, 'char16');
		ctx = append(ctx, uint16(v(:)));
	else
		ctx = fail(ctx, 'unicodeChar');
	end
end

function ctx = encCell(ctx, v)
	ctx = encTag(ctx, v, 'cell');
	for i = 1:numel(v)
		ctx = encAny(ctx, v{i});
	end
end

function ctx = encStruct(ctx, v)
	fields = fieldnames(v);
	if isempty(fields)
		fields = reshape(fields, 0, 0);
	end
	ctx = encTag(ctx, v, 'struct');
	ctx = encCell(ctx, fields);
	for i = 1:numel(fields)
		for j = 1:numel(v)
			% Coder requires fields{i} to be used directly
			ctx = encAny(ctx, v(j).(fields{i}));
		end
	end
end

function ctx = encTag(ctx, v, cls)
	tag = cls2cid(cls);
	if ~tag
		ctx = fail(ctx, 'unsupported');
	end
	if isscalar(v)
		ctx = appendBytes(ctx, tag);
		return;
	end
	maxsz = max(size(v));  % Not the same as length(v) for empty v
	if maxsz > intmax('uint8') || ~ismatrix(v)
		if ndims(v) > intmax('uint8') || (isempty(ctx.cgen) && ndims(v) > 2)
			ctx = fail(ctx, 'ndimsRange');
		end
		sz = size(v);
		if numel(v) > intmax || (isempty(v) && prod(sz(sz ~= 0)) > intmax)
			ctx = fail(ctx, 'numelRange');
		end
		cid = minUint(maxsz);
		ctx = appendBytes(ctx, [tag+bitshift(4+cid,5), uint8(ndims(v))]);
		switch cid
		case 1
			ctx = append(ctx, uint8(size(v)));
		case 2
			ctx = append(ctx, uint16(size(v)));
		case 3
			ctx = append(ctx, uint32(size(v)));
		end
	elseif maxsz == 0
		ctx = appendBytes(ctx, tag+128);
	elseif iscolumn(v)
		ctx = appendBytes(ctx, [tag+32, uint8(size(v,1))]);
	elseif isrow(v)
		ctx = appendBytes(ctx, [tag+64, uint8(size(v,2))]);
	else
		ctx = appendBytes(ctx, [tag+64+32, uint8(size(v))]);
	end
end

function ctx = append(ctx, v)
	if ctx.swap
		v = swapbytes(v);
	end
	ctx = appendBytes(ctx, typecast(v,'uint8'));
end

function ctx = appendBytes(ctx, v)
	n = int32(numel(ctx.buf));
	i = ctx.len + 1;
	ctx.len = ctx.len + numel(v);
	if ctx.len > n
		if n == 0
			return;
		elseif ctx.len > intmax - 3
			ctx = fail(ctx, 'overflow');
			return;
		end
		ctx.buf = [ctx.buf; zeros(max(n/2,ctx.len-n), 1, 'uint8')];
	end
	ctx.buf(i:ctx.len) = v(:);
end

function ctx = fail(ctx, id)
	if isempty(ctx.err)
		ctx.err = id;
		ctx.buf = zeros(0, 1, 'uint8');
	end
	if isempty(ctx.cgen)
		return;  % TODO: Still throw from mex files?
	end
	switch id
	case 'invalidByteOrder'
		msg = 'Byte order must be one of '''', ''B'', or ''L''.';
	case 'invalidSig'
		msg = 'Invalid buffer signature.';
	case 'overflow'
		msg = 'Buffer size limit exceeded.';
	case 'unsupported'
		msg = 'Unsupported data type.';
	case 'unicodeChar'
		msg = '16-bit characters are not supported.';
	case 'ndimsRange'
		msg = 'Number of dimensions exceeds uint8 range.';
	case 'numelRange'
		msg = 'Number of elements exceeds int32 range.';
	case ''
		msg = '';
	end
	error([mfilename ':' id], msg);
end

function cid = cls2cid(cls)
	cid = uint8(0);
	switch cls
	case 'double';  cid = uint8(1);
	case 'single';  cid = uint8(2);
	case 'int8';    cid = uint8(3);
	case 'uint8';   cid = uint8(4);
	case 'int16';   cid = uint8(5);
	case 'uint16';  cid = uint8(6);
	case 'int32';   cid = uint8(7);
	case 'uint32';  cid = uint8(8);
	case 'int64';   cid = uint8(9);
	case 'uint64';  cid = uint8(10);
	case 'logical'; cid = uint8(11);
	case 'char8';   cid = uint8(12);
	case 'char16';  cid = uint8(13);
	case 'cell';    cid = uint8(14);
	case 'struct';  cid = uint8(15);
	case 'sparse';  cid = uint8(16);
	case 'complex'; cid = uint8(17);
	end
end

function cid = minUint(maxval)
	if maxval <= intmax('uint8')
		cid = uint8(1);
	elseif maxval <= intmax('uint16')
		cid = uint8(2);
	elseif maxval <= intmax('uint32')
		cid = uint8(3);
	else
		cid = uint8(0);
	end
end
