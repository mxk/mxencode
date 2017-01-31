%MXENCODE   Serialize data into a byte array.
%   BUF = MXENCODE(V) encodes V, which may be numeric (including complex),
%   logical, char, cell, struct, sparse, or any combination thereof, into a
%   uint8 array. Use MXDECODE to extract the original value from BUF.
%
%   BUF = MXENCODE(V,BYTEORDER) encodes V using the specified BYTEORDER, which
%   must be one of 'B', 'L', or 'N' for big-endian, little-endian, or native
%   byte order, respectively. The default is native.
%
%   BUF = MXENCODE(V,BYTEORDER,VERSION) encodes the specified VERSION into the
%   first two bytes of BUF. VERSION must be a valid uint16 value with distinct
%   high and low bytes to enable byte order detection. The default version is
%   the answer to the ultimate question of life, the universe, and everything.
%
%   MXENCODE and MXDECODE were written primarily for use with MATLAB Coder to
%   serve as an efficient data exchange format between MATLAB and non-MATLAB
%   code. Since MATLAB Coder does not support sparse matrices as of R2016b, any
%   sparse matrix will be converted to a full matrix when BUF is decoded in
%   standalone mode.
%
%   BUF format (FIELD(#BYTES)): [ VERSION(2) VALUE(1-N) PAD(1-4) ]
%
%   VERSION allows the decoder to identify a valid buffer and to determine the
%   byte ordering that was used for encoding.
%
%   VALUE is a recursive encoding of V based on its class. The first byte is a
%   tag in which the lower 5 bits specify the class and the upper 3 bits specify
%   size encoding format:
%      0 = scalar (1x1): [ TAG(1) DATA ]
%      1 = row vector (1xN) with N < 256: [ TAG(1) N(1) DATA ]
%      2 = column vector (Mx1) with M < 256: [ TAG(1) M(1) DATA ]
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
%      Maximum number of array elements: 4,294,967,295
%      Maximum buffer size: 4,294,967,292
%
%   See also MXDECODE, TYPECAST, COMPUTER.

%   Written by Maxim Khitrov (January 2017)

function buf = mxencode(v, byteOrder, vers)  %#codegen
	narginchk(1, 3);
	if nargin < 2 || strcmp(byteOrder,'N')
		swap = false;
	else
		byteOrder = validatestring(byteOrder, {'N','B','L'}, 2);
		native = char(bitand(typecast(uint8('LB'),'uint16'), 255));
		swap = ~(strcmp(byteOrder,'N') || strcmp(byteOrder,native));
	end
	if nargin < 3
		vers = uint16(42);
	end
	buf = zeros(64, 1, 'uint8');
	coder.varsize('buf');
	[buf,len] = appendAny(buf, uint32(0), swap, uint16(vers));
	if buf(1) == buf(2)
		buf = fail('invalidVersion', 'invalid version value');
		return;
	end
	[buf,len] = encAny(buf, len, swap, v);
	pad = uint8(4 - bitand(len,3));
	[buf,len] = append(buf, len, repmat(bitcmp(pad),pad,1));
	if ~isempty(buf)
		buf = buf(1:len);
	end
end

function [buf,len] = encAny(buf, len, swap, v)
	if isnumeric(v)
		[buf,len] = encNumeric(buf, len, swap, v);
	elseif islogical(v)
		[buf,len] = encLogical(buf, len, swap, v);
	elseif ischar(v)
		[buf,len] = encChar(buf, len, swap, v);
	elseif iscell(v)
		[buf,len] = encCell(buf, len, swap, v);
	elseif isstruct(v)
		[buf,len] = encStruct(buf, len, swap, v);
	else
		buf = fail('unsupported', ['unsupported class: ' class(v)]);
	end
end

function [buf,len] = encNumeric(buf, len, swap, v)
	if issparse(v)
		[buf,len] = encSparse(buf, len, swap, v);
	elseif isreal(v)
		[buf,len] = encTag(buf, len, swap, v, class(v));
		[buf,len] = appendAny(buf, len, swap, v(:));
	else
		[buf,len] = encTag(buf, len, swap, v, 'complex');
		[buf,len] = encTag(buf, len, swap, 0, class(v));
		[buf,len] = appendAny(buf, len, swap, real(v(:)));
		[buf,len] = appendAny(buf, len, swap, imag(v(:)));
	end
end

function [buf,len] = encLogical(buf, len, swap, v)
	if issparse(v)
		[buf,len] = encSparse(buf, len, swap, v);
	else
		[buf,len] = encTag(buf, len, swap, v, 'logical');
		[buf,len] = append(buf, len, uint8(v(:)));
	end
end

function [buf,len] = encSparse(buf, len, swap, v)
	idx = find(v);
	if isempty(idx)
		idx = reshape(idx, 0, 0);
	else
		[~,cls] = pickCls(idx(end));
		if ~isempty(cls)
			idx = cast(idx, cls);
		end
	end
	[buf,len] = encTag(buf, len, swap, v, 'sparse');
	[buf,len] = encNumeric(buf, len, swap, idx);
	[buf,len] = encAny(buf, len, swap, full(v(idx)));
end

function [buf,len] = encChar(buf, len, swap, v)
	if all(v <= intmax('uint8'))
		[buf,len] = encTag(buf, len, swap, v, 'char8');
		[buf,len] = append(buf, len, uint8(v(:)));
	else
		[buf,len] = encTag(buf, len, swap, v, 'char16');
		[buf,len] = appendAny(buf, len, swap, uint16(v(:)));
	end
end

function [buf,len] = encCell(buf, len, swap, v)
	[buf,len] = encTag(buf, len, swap, v, 'cell');
	for i = 1:numel(v)
		[buf,len] = encAny(buf, len, swap, v{i});
	end
end

function [buf,len] = encStruct(buf, len, swap, v)
	fields = fieldnames(v);
	if isempty(fields)
		fields = reshape(fields, 0, 0);
	end
	[buf,len] = encTag(buf, len, swap, v, 'struct');
	[buf,len] = encCell(buf, len, swap, fields);
	for i = 1:numel(fields)
		field = fields{i};
		for j = 1:numel(v)
			[buf,len] = encAny(buf, len, swap, v(j).(field));
		end
	end
end

function [buf,len] = encTag(buf, len, swap, v, cls)
	classes = {'double','single','logical','char8','char16','cell','struct', ...
			'int8','uint8','int16','uint16','int32','uint32','int64', ...
			'uint64','sparse','complex'};
	tag = uint8(find(strcmp(cls,classes), 1));
	if isempty(tag)
		buf = fail('unsupported', ['unsupported class: ' cls]);
		return;
	end
	if isscalar(v)
		[buf,len] = append(buf, len, tag);
		return;
	end
	maxsz = max(size(v));  % Not the same as length(v) for empty v
	if maxsz > intmax('uint8') || ~ismatrix(v)
		if ndims(v) > intmax('uint8')
			buf = fail('ndimsRange', 'ndims exceeds uint8 range');
			return;
		end
		if numel(v) > intmax('uint32')
			buf = fail('numelRange', 'numel exceeds uint32 range');
			return;
		end
		[cid,cls] = pickCls(maxsz);
		[buf,len] = append(buf, len, [tag+bitshift(4+cid,5); uint8(ndims(v))]);
		[buf,len] = appendAny(buf, len, swap, cast(size(v),cls));
	elseif maxsz == 0
		[buf,len] = append(buf, len, tag+128);
	elseif iscolumn(v)
		[buf,len] = append(buf, len, [tag+64; uint8(size(v,1))]);
	elseif isrow(v)
		[buf,len] = append(buf, len, [tag+32; uint8(size(v,2))]);
	else
		[buf,len] = append(buf, len, [tag+64+32; uint8(size(v)')]);
	end
end

function [cid,cls] = pickCls(maxval)
	lim = [uint32(intmax('uint8')),intmax('uint16'),intmax('uint32')];
	cid = uint8(find(maxval <= lim, 1));
	if ~isempty(cid)
		fmt = {'uint8','uint16','uint32'};
		cls = fmt{cid};
	else
		cid = uint8(0);
		cls = '';
	end
end

function [buf,len] = appendAny(buf, len, swap, v)
	if swap
		v = swapbytes(v);
	end
	[buf,len] = append(buf, len, typecast(v,'uint8'));
end

function [buf,len] = append(buf, len, v)
	n = uint32(numel(buf));
	i = len + 1;
	len = len + numel(v);
	if len > n
		if n == 0
			return;
		elseif len > intmax('uint32') - 3
			buf = fail('overflow', 'buffer overflow');
			return;
		end
		buf = [buf; zeros(max(n/2,len-n),1,'uint8')];
	end
	buf(i:len) = v(:);
end

function buf = fail(id, msg)
	if coder.target('MATLAB')
		error(['mxencode:' id], msg);
	end
	buf = reshape(uint8([]), 0, 1);
end
