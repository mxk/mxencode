%MXDECODE   Deserialize data from a byte array.
%   V = MXDECODE(BUF) decodes the original value V from uint8 array BUF.
%
%   V = MXDECODE(BUF,VERSION) uses the specified VERSION to identify a valid
%   buffer and determine the correct byte order for decoding.
%
%   See also MXENCODE.

%   Written by Maxim Khitrov (January 2017)

function v = mxdecode(buf, vers)  %#codegen
	narginchk(1, 2);
	swap = false;
	n = uint32(numel(buf));
	if n == 0 || bitand(n,3) ~= 0 || ~isa(buf,'uint8') || ~isreal(buf) || ...
			~iscolumn(buf) || buf(1) == buf(2)
		v = fail('invalidBuf', 'invalid buffer');
		return;
	end
	if nargin < 2
		vers = uint16(42);
	end
	switch typecast(buf(1:2), 'uint16')
	case uint16(vers)
	case swapbytes(uint16(vers))
		swap = true;
	otherwise
		v = fail('invalidFormat', 'invalid buffer format');
		return;
	end
	[v,pos] = decNext(buf, uint32(3), swap);
	pad = uint32(bitcmp(buf(n)));
	if pad > 4 || pos + pad - 1 ~= n || any(buf(pos:n-1) ~= buf(n))
		v = fail('corrupt', 'corrupt buffer');
	end
end

function [v,pos] = decNext(buf, pos, swap)
	[cls,bpe,vsz,pos] = decTag(buf, pos, swap);
	n = prod(vsz, 'native');
	switch cls
	case 'logical'
		[v,pos] = decLogical(buf, pos, n);
	case 'char'
		[v,pos] = decChar(buf, pos, swap, n, bpe);
	case 'cell'
		[v,pos] = decCell(buf, pos, swap, n);
	case 'struct'
		[v,pos] = decStruct(buf, pos, swap, n);
	case 'sparse'
		[v,pos] = decSparse(buf, pos, swap, n);
	case 'complex'
		[v,pos] = decComplex(buf, pos, swap, n);
	otherwise
		[v,pos] = decNumeric(buf, pos, swap, n*bpe, cls);
	end
	if pos <= numel(buf)
		v = reshape(v, vsz);
	end
end

function [v,pos] = decNumeric(buf, pos, swap, n, cls)
	if ~isempty(cls)
		[i,j,pos] = consume(buf, pos, n);
		v = typecast(buf(i:j), cls);
		if swap
			v = swapbytes(v);
		end
	else
		v = [];
	end
end

function [v,pos] = decComplex(buf, pos, swap, n)
	[cls,bpe,~,pos] = decTag(buf, pos, swap);
	n = n*bpe;
	[re,pos] = decNumeric(buf, pos, swap, n, cls);
	[im,pos] = decNumeric(buf, pos, swap, n, cls);
	v = complex(re, im);
end

function [v,pos] = decLogical(buf, pos, n)
	[i,j,pos] = consume(buf, pos, n);
	v = logical(buf(i:j));
end

function [v,pos] = decSparse(buf, pos, swap, n)
	[idx,pos] = decNext(buf, pos, swap);
	[nze,pos] = decNext(buf, pos, swap);
	if coder.target('MATLAB')
		v = sparse(double(idx), 1, nze, double(n), 1);
	else
		v = zeros(n, 1, class(nze));
		v(idx) = nze;
	end
end

function [v,pos] = decChar(buf, pos, swap, n, bpe)
	if bpe == 1
		[i,j,pos] = consume(buf, pos, n);
		v = char(buf(i:j));
	else
		[v,pos] = decNumeric(buf, pos, swap, n*2, 'uint16');
		v = char(v);
	end
end

function [v,pos] = decCell(buf, pos, swap, n)
	v = cell(n, 1);
	for i = 1:n
		[v{i},pos] = decNext(buf, pos, swap);
	end
end

function [v,pos] = decStruct(buf, pos, swap, n)
	[fields,pos] = decNext(buf, pos, swap);
	if isempty(fields) || ~iscell(fields)
		v = struct([]);
		return;
	end
	fieldvals = cell(1, 2*numel(fields));
	fieldvals(1:2:numel(fieldvals)) = fields;
	for i = 2:2:numel(fieldvals)
		vals = cell(n, 1);
		for j = 1:n
			[vals{j},pos] = decNext(buf, pos, swap);
		end
		fieldvals{i} = vals;
	end
	v = struct(fieldvals{:});
end

function [cls,bpe,vsz,pos] = decTag(buf, pos, swap)
	[i,~,pos] = consume(buf, pos, 1);
	cid = bitand(buf(i), 31);
	szf = bitshift(buf(i), -5);
	switch szf
	case 0
		vsz = ones(1, 2, 'uint32');
	case 1
		[i,~,pos] = consume(buf, pos, 1);
		vsz = uint32([1,buf(i)]);
	case 2
		[i,~,pos] = consume(buf, pos, 1);
		vsz = uint32([buf(i),1]);
	case 3
		[i,j,pos] = consume(buf, pos, 2);
		vsz = uint32(buf(i:j)');
	case 4
		vsz = zeros(1, 2, 'uint32');
	otherwise
		fmt = {'uint8','uint16','uint32'};
		szf = bitand(szf, 3);
		[i,~,pos] = consume(buf, pos, 1);
		szn = uint32(buf(i)) * bitshift(uint32(1),szf-1);
		[vsz,pos] = decNumeric(buf, pos, swap, szn, fmt{szf});
		vsz = uint32(vsz');
	end
	classes = {'double','single','logical','char','char','cell','struct', ...
			'int8','uint8','int16','uint16','int32','uint32','int64', ...
			'uint64','sparse','complex'};
	bytesPerElement = uint32([8,4,1,1,2,0,0,1,1,2,2,4,4,8,8,0,0]);
	if pos <= numel(buf) && 1 <= cid && cid <= numel(classes)
		cls = classes{cid};
		bpe = bytesPerElement(cid);
	else
		cls = '';
		bpe = uint32(0);
		vsz = zeros(1, 2, 'uint32');
		pos = intmax('uint32');
	end
end

function [i,j,pos] = consume(buf, pos, n)
	i = pos;
	j = pos + n - 1;
	pos = pos + n;
	if j >= numel(buf)  % TODO: isempty(n) possible?
		i = uint32(1);
		j = uint32(0);
		pos = intmax('uint32');
	end
end

function v = fail(id, msg)
	if coder.target('MATLAB')
		error(['mxdecode:' id], msg);
	end
	v = [];
end
