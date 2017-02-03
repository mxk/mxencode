%MXENCODE   Serialize data into a byte array.
%   BUF = MXENCODE(V) encodes V, which may be numeric (including complex),
%   logical, char, cell, struct, sparse, or any combination thereof, into a
%   uint8 array. Use MXDECODE to extract the original value from BUF.
%
%   BUF = MXENCODE(V,BYTEORDER) encodes V using the specified BYTEORDER, which
%   must be one of '', 'B', or 'L' for native, big-endian, or little-endian,
%   respectively. The default is native.
%
%   BUF = MXENCODE(V,BYTEORDER,SIG) encodes the specified SIG into the first two
%   signature bytes. SIG must be a uint16 value with distinct high and low bytes
%   to enable byte order detection. The default signature is the answer to the
%   ultimate question of life, the universe, and everything.
%
%   BUF = MXENCODE(V,BYTEORDER,SIG,CGEN) enables standalone mode when CGEN is
%   set to true. This form must be used when generating C/C++ code with MATLAB
%   Coder. It disables the use of the error function, returning an empty buf
%   instead when an error occurs.
%
%   MXENCODE and MXDECODE were written primarily for use with MATLAB Coder to
%   serve as an efficient data exchange format between MATLAB and non-MATLAB
%   code. Multiple restrictions are placed on the encoded data when these
%   functions are compiled for standalone use. See MXDECODE for more info.
%
%   BUF format (FIELD(#BYTES)): [ SIG(2) VALUE(1-N) PAD(1-4) ]
%
%   SIG contains two signature bytes that allow the decoder to identify a valid
%   buffer and to determine the byte ordering that was used during encoding.
%
%   VALUE is a recursive encoding of V based on its class. The first byte is a
%   tag in which the lower 5 bits specify the class and the upper 3 bits specify
%   size encoding format:
%      0 = scalar (1x1): [ TAG(1) DATA ]
%      1 = column vector (Mx1) with M < 256: [ TAG(1) M(1) DATA ]
%      2 = row vector (1xN) with N < 256: [ TAG(1) N(1) DATA ]
%      3 = matrix (MxN) with M < 256 and N < 256: [ TAG(1) M(1) N(1) DATA ]
%      4 = empty value (0x0): [ TAG(1) ]
%      5 = uint8 general format: [ TAG(1) NDIMS(1) SIZE1(1) SIZE2(1) ... DATA ]
%      6 = uint16 general format: [ TAG(1) NDIMS(1) SIZE1(2) SIZE2(2) ... DATA ]
%      7 = uint32 general format: [ TAG(1) NDIMS(1) SIZE1(4) SIZE2(4) ... DATA ]
%
%   PAD contains 1-4 bytes all set to the bitwise complement of PAD length. It
%   serves as an explicit end-of-data marker and ensures that BUF contains a
%   multiple of 4 bytes.
%
%   Limits:
%      Maximum number of array dimensions: 255
%      Maximum number of array elements: 2,147,483,647
%      Maximum buffer size: 2,147,483,644
%
%   See also MXDECODE, TYPECAST, COMPUTER.

%   Written by Maxim Khitrov (February 2017)

function buf = mxencode(v, byteOrder, sig, cgen)  %#codegen
	narginchk(1, 4);
	cgen = (nargin == 4 && cgen);
	ctx = struct( ...
		'buf',  zeros(64, 1, 'uint8'), ...
		'len',  int32(0), ...
		'swap', false, ...
		'cgen', cgen ...
	);
	if cgen
		coder.cstructname(ctx, 'Ctx');
		coder.varsize('ctx.buf');
	end
	if nargin >= 2 && ~isempty(byteOrder)
		if byteOrder == 'B' || byteOrder == 'L'
			native = char(bitand(typecast(uint8('LB'),'uint16'), 255));
			ctx.swap = (byteOrder ~= native);
		else
			ctx = fail(ctx, 'invalidByteOrder', ...
					'byte order must be one of '''', ''B'', or ''L''');
		end
	end
	if nargin >= 3 && ~isempty(sig)
		sig = uint16(sig);
		if bitand(sig, 255) == bitshift(sig, -8)
			ctx = fail(ctx, 'invalidSig', 'both signature bytes are identical');
		end
	else
		sig = uint16(42);
	end
	ctx = append(ctx, sig);
	ctx = encAny(ctx, v);
	pad = uint8(4 - bitand(ctx.len,3));
	ctx = appendBytes(ctx, repmat(bitcmp(pad),pad,1));
	if ~isempty(ctx.buf)
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
		ctx = fail(ctx, 'unsupported', ['unsupported class: ' class(v)]);
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
		cid = pickCls(idx(end));
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
		ctx = encNumeric(ctx, idx);
	end
	ctx = encAny(ctx, full(v(idx)));
end

function ctx = encChar(ctx, v)
	if all(v(:) <= intmax('uint8'))
		ctx = encTag(ctx, v, 'char8');
		ctx = appendBytes(ctx, uint8(v(:)));
	else
		ctx = encTag(ctx, v, 'char16');
		ctx = append(ctx, uint16(v(:)));
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
			% Coder complains if fields{i} is stored in another variable
			ctx = encAny(ctx, v(j).(fields{i}));
		end
	end
end

function ctx = encTag(ctx, v, cls)
	classes = {'double','single','logical','char8','char16','cell','struct', ...
			'int8','uint8','int16','uint16','int32','uint32','int64', ...
			'uint64','sparse','complex'};
	tag = uint8(find(strcmp(cls,classes), 1));
	if isempty(tag)
		ctx = fail(ctx, 'unsupported', ['unsupported class: ' cls]);
	end
	if isscalar(v)
		ctx = appendBytes(ctx, tag);
		return;
	end
	maxsz = max(size(v));  % Not the same as length(v) for empty v
	if maxsz > intmax('uint8') || ~ismatrix(v)
		if ndims(v) > intmax('uint8')
			ctx = fail(ctx, 'ndimsRange', 'ndims exceeds uint8 range');
		end
		if numel(v) > intmax
			ctx = fail(ctx, 'numelRange', 'numel exceeds int32 range');
		end
		if maxsz > intmax
			ctx = fail(ctx, 'maxSize', 'max(size) exceeds int32 range');
		end
		cid = pickCls(maxsz);
		ctx = appendBytes(ctx, [tag+bitshift(4+cid,5); uint8(ndims(v))]);
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
		ctx = appendBytes(ctx, [tag+32; uint8(size(v,1))]);
	elseif isrow(v)
		ctx = appendBytes(ctx, [tag+64; uint8(size(v,2))]);
	else
		ctx = appendBytes(ctx, [tag+64+32; uint8(size(v)')]);
	end
end

function cid = pickCls(maxval)
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
			ctx = fail(ctx, 'overflow', 'buffer size limit exceeded');
			return;
		end
		ctx.buf = [ctx.buf; zeros(max(n/2,ctx.len-n),1,'uint8')];
	end
	ctx.buf(i:ctx.len) = v(:);
end

function ctx = fail(ctx, id, msg)
	if ctx.cgen
		ctx.buf = zeros(0, 1, 'uint8');
	else
		error([mfilename ':' id], msg);
	end
end
