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
%     its message id (just the mnemonic) and BUF will be empty. Compiled MEX
%     functions will still throw errors for testing purposes.
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
%   order detection, the low byte must always be less than 240.
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
%     Maximum number of array dimensions: 255 (2 in standalone mode)
%     Maximum number of array elements: 2,147,483,647
%     Maximum buffer size: 2,147,483,644
%
%   See also MXDECODE, TYPECAST, SWAPBYTES, COMPUTER.

%   Written by Maxim Khitrov (February 2017)

function [buf,err] = mxencode(v, sig, byteOrder)  %#codegen
	cgen = (nargout == 2);
	narginchk(1, 3);
	maySwap = (nargin == 3 && ~isempty(byteOrder));
	ctx = struct( ...
		'swap', false(int32(maySwap)), ...  % Empty is compile-time false
		'cgen', false(int32(~cgen)), ...    % Empty is compile-time true
		'err',  '' ...
	);
	if cgen
		coder.cstructname(ctx, 'MxEncCtx');
		coder.varsize('ctx.err', [1,32]);
		coder.varsize('buf', [Inf,1]);
	end

	% Set buffer signature
	fmt = uint16(240);
	usr = uint16(42);
	if nargin >= 2 && ~isempty(sig)
		if isscalar(sig) && uint16(sig) < 240
			usr = uint16(sig);
		else
			ctx = fail(ctx, 'invalidSig');
		end
	end

	% Set encoder byte order
	if maySwap
		if byteOrder == 'B' || byteOrder == 'L'
			native = char(bitand(typecast(uint8('LB'),'uint16'), 255));
			ctx.swap = (byteOrder ~= native);
		else
			ctx = fail(ctx, 'invalidByteOrder');
		end
	end

	% Buffer had to be moved out of ctx because Coder generated really
	% inefficient code otherwise, making a copy of ctx between each append call
	% and immediately freeing the original.
	buf = zeros(0, 1, 'uint8');

	% Encode
	if isempty(ctx.err)
		if cgen && ~coder.target('MATLAB')
			% Pre-allocate 4KB buffer. The first append will reduce its size but
			% keep the capacity (doing that here eliminates pre-allocation).
			buf = coder.nullcopy(zeros(4096, 1, 'uint8'));
			buf(1:2) = uint8(0);
		end
		[ctx,buf] = append(ctx, buf, bitshift(fmt,8)+usr);
		[ctx,buf] = encAny(ctx, buf, v);
		pad = uint8(4 - bitand(uint32(numel(buf)),3));
		[ctx,buf] = appendBytes(ctx, buf, repmat(bitcmp(pad),pad,1));

		% Sanity check for coder.nullcopy hack in appendBytes
		if cgen && ~((buf(1) == usr && buf(2) == fmt) || ...
				(buf(1) == fmt && buf(2) == usr))
			ctx = fail(ctx, 'bufResize');
		end
		if ~isempty(ctx.err)
			buf = zeros(0, 1, 'uint8');
		end
	end
	err = ctx.err;
end

function [ctx,buf] = encAny(ctx, buf, v)
	if isnumeric(v)
		[ctx,buf] = encNumeric(ctx, buf, v);
	elseif islogical(v)
		[ctx,buf] = encLogical(ctx, buf, v);
	elseif ischar(v)
		[ctx,buf] = encChar(ctx, buf, v);
	elseif iscell(v)
		[ctx,buf] = encCell(ctx, buf, v);
	elseif isstruct(v)
		[ctx,buf] = encStruct(ctx, buf, v);
	else
		ctx = fail(ctx, 'unsupportedClass', true);
	end
end

function [ctx,buf] = encNumeric(ctx, buf, v)
	if issparse(v)
		[ctx,buf] = encSparse(ctx, buf, v);
	elseif isreal(v)
		[ctx,buf] = encTag(ctx, buf, v, class(v));
		[ctx,buf] = append(ctx, buf, v(:));
	else
		[ctx,buf] = encTag(ctx, buf, v, 'complex');
		[ctx,buf] = encTag(ctx, buf, 0, class(v));
		[ctx,buf] = append(ctx, buf, real(v(:)));
		[ctx,buf] = append(ctx, buf, imag(v(:)));
	end
end

function [ctx,buf] = encLogical(ctx, buf, v)
	if issparse(v)
		[ctx,buf] = encSparse(ctx, buf, v);
	else
		[ctx,buf] = encTag(ctx, buf, v, 'logical');
		[ctx,buf] = appendBytes(ctx, buf, uint8(v(:)));
	end
end

function [ctx,buf] = encSparse(ctx, buf, v)
	[ctx,buf] = encTag(ctx, buf, v, 'sparse');
	idx = find(v);
	if isempty(idx)
		idx = reshape(idx, 0, 0);
		cid = uint8(1);
	else
		cid = minUint(idx(end));
	end
	switch cid
	case 1; [ctx,buf] = encNumeric(ctx, buf, uint8(idx));
	case 2; [ctx,buf] = encNumeric(ctx, buf, uint16(idx));
	case 3; [ctx,buf] = encNumeric(ctx, buf, uint32(idx));
	end
	[ctx,buf] = encAny(ctx, buf, full(v(idx)));  % Double or logical
end

function [ctx,buf] = encChar(ctx, buf, v)
	if all(v(:) <= intmax('uint8'))
		[ctx,buf] = encTag(ctx, buf, v, 'char8');
		[ctx,buf] = appendBytes(ctx, buf, uint8(v(:)));
	else
		[ctx,buf] = encTag(ctx, buf, v, 'char16');
		[ctx,buf] = append(ctx, buf, uint16(v(:)));
	end
end

function [ctx,buf] = encCell(ctx, buf, v)
	[ctx,buf] = encTag(ctx, buf, v, 'cell');
	for i = 1:numel(v)
		[ctx,buf] = encAny(ctx, buf, v{i});
	end
end

function [ctx,buf] = encStruct(ctx, buf, v)
	[ctx,buf] = encTag(ctx, buf, v, 'struct');
	fields = fieldnames(v);
	if isempty(fields)
		fields = reshape(fields, 0, 0);
	end
	[ctx,buf] = encCell(ctx, buf, fields);
	for i = 1:numel(fields)
		for j = 1:numel(v)
			% Coder requires fields{i} to be used directly
			[ctx,buf] = encAny(ctx, buf, v(j).(fields{i}));
		end
	end
end

function [ctx,buf] = encTag(ctx, buf, v, cls)
	tag = cls2cid(cls);
	assert(tag > 0);
	if isscalar(v)
		[ctx,buf] = appendBytes(ctx, buf, tag);
		return;
	end
	maxsz = max(size(v));  % Not the same as length(v) for empty v
	if ~ismatrix(v) || maxsz > intmax('uint8')
		if ndims(v) > intmax('uint8') || (isempty(ctx.cgen) && ~ismatrix(v))
			ctx = fail(ctx, 'ndimsLimit', true);
		end
		sz = size(v);
		if numel(v) > intmax || (isempty(v) && prod(sz(sz ~= 0)) > intmax)
			ctx = fail(ctx, 'numelLimit');
		end
		cid = minUint(maxsz);
		[ctx,buf] = appendBytes(ctx, buf, [tag+bitshift(4+cid,5); ndims(v)]);
		switch cid
		case 1; [ctx,buf] = append(ctx, buf, uint8(size(v)));
		case 2; [ctx,buf] = append(ctx, buf, uint16(size(v)));
		case 3; [ctx,buf] = append(ctx, buf, uint32(size(v)));
		end
	elseif maxsz == 0
		[ctx,buf] = appendBytes(ctx, buf, tag+128);
	elseif iscolumn(v)
		[ctx,buf] = appendBytes(ctx, buf, [tag+32; size(v,1)]);
	elseif isrow(v)
		[ctx,buf] = appendBytes(ctx, buf, [tag+64; size(v,2)]);
	else
		[ctx,buf] = appendBytes(ctx, buf, [tag+64+32; size(v,1); size(v,2)]);
	end
end

function [ctx,buf] = append(ctx, buf, v)
	if ctx.swap
		bytes = typecast(swapbytes(v), 'uint8');
	else
		bytes = typecast(v, 'uint8');
	end
	[ctx,buf] = appendBytes(ctx, buf, bytes(:));
end

function [ctx,buf] = appendBytes(ctx, buf, bytes)
	i = int32(numel(buf)) + 1;
	j = int32(numel(buf)) + int32(numel(bytes));
	if j > intmax - 3 || ~isempty(ctx.err)
		ctx = fail(ctx, 'bufLimit');
	elseif ~isempty(ctx.cgen) || coder.target('MATLAB')
		buf(i:j) = bytes;
	else
		if buf(1) == buf(2)
			% First append to pre-allocated buf
			i = int32(1);
			j = int32(numel(bytes));
		end

		% Barrier to evaluate i and j (see mxdecode for explanation)
		coder.ceval('(void)', coder.ref(i), coder.ref(j));

		% HACK: Call emxEnsureCapacity without creating additional buf copies
		buf = coder.nullcopy(zeros(j, 1, 'uint8'));
		coder.ceval('memcpy', coder.wref(buf(i)), coder.rref(bytes), ...
				int32(numel(bytes)));
	end
end

function ctx = fail(ctx, err, codegenErr)
	if isempty(ctx.err)
		ctx.err = err;
	end
	switch err
	case 'bufLimit'
		msg = 'Buffer size exceeds limit.';
	case 'bufResize'
		msg = 'Buffer resize via coder.nullcopy failed.';
	case 'invalidByteOrder'
		msg = 'Byte order must be one of '''', ''B'', or ''L''.';
	case 'invalidSig'
		msg = 'Invalid buffer signature (must be scalar < 240).';
	case 'ndimsLimit'
		msg = 'Number of dimensions exceeds limit.';
	case 'numelLimit'
		msg = 'Number of elements exceeds limit.';
	case 'unsupportedClass'
		msg = 'Unsupported object class.';
	end
	err = [mfilename ':' err];
	if ~isempty(ctx.cgen) || (coder.target('MEX') && nargin < 3)
		error(err, msg);
	elseif nargin == 3
		coder.inline(err);  % HACK: Generate errors during codegen execution
	end
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
