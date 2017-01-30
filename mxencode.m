%MXENCODE   Serialize data into a byte array.
%   BUF = MXENCODE(V) encodes V, which may be numeric (including complex),
%   logical, char, cell, struct, sparse, or any combination thereof, into a
%   uint8 array. Use MXDECODE to extract the original value from BUF.
%
%   MXENCODE and MXDECODE were written primarily for use with MATLAB Coder to
%   serve as an efficient data exchange format between MATLAB and non-MATLAB
%   code. Since MATLAB Coder does not support sparse matrices as of R2016b, any
%   sparse matrix will be converted to a full matrix when BUF is decoded in
%   standalone mode.
%
%   BUF format (FIELD(#BYTES)): [ VERSION(2) VALUE(1-N) PAD(1-4) ]
%
%   VERSION is incremented for all backward-incompatible changes to the encoding
%   format. The current version is 42. This is also a byte order mark, with the
%   upper byte always set to 0. All fields are encoded using the native byte
%   order. MXDECODE does not support decoding non-native BUFs.
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
%      Maximum number of struct fields: 65,535
%      Maximum buffer size: 4,294,967,294
%
%   See also MXDECODE, TYPECAST.

%   Written by Maxim Khitrov (January 2017)

function buf = mxencode(v)  %#codegen
	buf = zeros(64, 1, 'uint8');
	buf(1:2) = typecast(uint16(42), 'uint8');
	[buf,len] = encAny(buf, uint32(2), v);
	pad = uint8(4 - bitand(len,3));
	[buf,len] = append(buf, len, repmat(bitcmp(pad),pad,1));
	buf = buf(1:len);
end

function [buf,len] = encAny(buf, len, v)
	if isnumeric(v)
		[buf,len] = encNumeric(buf, len, v);
	elseif islogical(v)
		[buf,len] = encLogical(buf, len, v);
	elseif ischar(v)
		[buf,len] = encChar(buf, len, v);
	elseif iscell(v)
		[buf,len] = encCell(buf, len, v);
	elseif isstruct(v)
		[buf,len] = encStruct(buf, len, v);
	else
		len = fail('unsupported', ['unsupported class: ' class(v)]);
	end
end

function [buf,len] = encNumeric(buf, len, v)
	if issparse(v)
		[buf,len] = encSparse(buf, len, v);
	elseif isreal(v)
		[buf,len] = encTag(buf, len, v, class(v));
		[buf,len] = append(buf, len, typecast(v(:),'uint8'));
	else
		[buf,len] = encTag(buf, len, v, 'complex');
		[buf,len] = encTag(buf, len, 0, class(v));
		[buf,len] = append(buf, len, typecast(real(v(:)),'uint8'));
		[buf,len] = append(buf, len, typecast(imag(v(:)),'uint8'));
	end
end

function [buf,len] = encLogical(buf, len, v)
	if issparse(v)
		[buf,len] = encSparse(buf, len, v);
	else
		[buf,len] = encTag(buf, len, v, 'logical');
		[buf,len] = append(buf, len, uint8(v(:)));
	end
end

function [buf,len] = encSparse(buf, len, v)
	idx = find(v);
	if isempty(idx)
		idx = reshape(idx, 0, 0);
	else
		[~,cls] = pickCls(idx(end));
		if ~isempty(cls)
			idx = cast(idx, cls);
		end
	end
	[buf,len] = encTag(buf, len, v, 'sparse');
	[buf,len] = encNumeric(buf, len, idx);
	[buf,len] = encAny(buf, len, full(v(idx)));
end

function [buf,len] = encChar(buf, len, v)
	if all(v <= intmax('uint8'))
		[buf,len] = encTag(buf, len, v, 'char8');
		[buf,len] = append(buf, len, uint8(v(:)));
	else
		[buf,len] = encTag(buf, len, v, 'char');
		[buf,len] = append(buf, len, typecast(uint16(v(:)),'uint8'));
	end
end

function [buf,len] = encCell(buf, len, v)
	[buf,len] = encTag(buf, len, v, 'cell');
	for i = 1:numel(v)
		[buf,len] = encAny(buf, len, v{i});
	end
end

function [buf,len] = encStruct(buf, len, v)
	fields = fieldnames(v);
	if numel(fields) > intmax('uint16')
		len = fail('fieldCount', 'struct field count exceeds uint16 range');
		return;
	end
	[buf,len] = encTag(buf, len, v, 'struct');
	[buf,len] = append(buf, len, typecast(uint16(numel(fields)),'uint8'));
	for i = 1:numel(fields)
		field = fields{i};
		[buf,len] = encChar(buf, len, field);
		for j = 1:numel(v)
			[buf,len] = encAny(buf, len, v(j).(field));
		end
	end
end

function [buf,len] = encTag(buf, len, v, cls)
	if len == 0
		return;
	end
	classes = {'double','single','logical','char','char8','cell','struct', ...
			'int8','uint8','int16','uint16','int32','uint32','int64', ...
			'uint64','sparse','complex'};
	tag = uint8(find(strcmp(cls,classes), 1));
	if isempty(tag)
		len = fail('unsupported', ['unsupported class: ' cls]);
		return;
	end
	if isscalar(v)
		[buf,len] = append(buf, len, tag);
		return;
	end
	maxsz = max(size(v));  % Not the same as length(v) for empty v
	if ~ismatrix(v) || maxsz > intmax('uint8')
		if ndims(v) > intmax('uint8')
			len = fail('ndimsRange', 'ndims exceeds uint8 range');
			return;
		end
		if numel(v) > intmax('uint32')
			len = fail('numelRange', 'numel exceeds uint32 range');
			return;
		end
		[cid,cls] = pickCls(maxsz);
		[buf,len] = append(buf, len, [tag+128+bitshift(cid,5); ...
				uint8(ndims(v)); typecast(cast(size(v)',cls),'uint8')]);
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

function [buf,len] = append(buf, len, v)
	if isempty(v) || len == 0
		return;
	end
	n = len + numel(v);
	if n > numel(buf)
		grow = max(2*numel(buf),n) - numel(buf);
		buf = [buf; zeros(grow,1,'uint8')];
		if numel(buf) >= intmax('uint32')
			len = fail('overflow', 'buffer overflow');
			return;
		end
	end
	buf(len+1:n) = v;
	len = n;
end

function len = fail(id, msg)
	if coder.target('MATLAB')
		error(['mxencode:' id], msg);
	end
	len = uint32(0);
end
