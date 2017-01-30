%MXDECODE   Deserialize data from a byte array.
%   V = MXDECODE(BUF) decodes the original value V from uint8 array BUF.
%
%   See also MXENCODE, TYPECAST.

%   Written by Maxim Khitrov (January 2017)

function v = mxdecode(buf)  %#codegen
	n = uint32(numel(buf));
	if isa(buf, 'uint8') && isreal(buf) && 4 <= n && n < intmax('uint32') && ...
			iscolumn(buf) && typecast(buf(1:2), 'uint16') == 42 && ...
			bitand(n, 3) == 0
		[v,pos] = decNext(buf, uint32(3));
		if pos <= n && n-pos <= 3 && all(buf(pos:end) == 255-(n-pos+1))
			return;
		end
	end
	if coder.target('MATLAB')
		error('mxdecode:invalidBuf', 'invalid buffer');
	end
	v = [];
end

function [v,pos] = decNext(buf, pos)
	[cls,bpe,vsz,pos] = decTag(buf, pos);
	n = prod(vsz, 'native');
	switch cls
	case 'logical'
		[v,pos] = decLogical(buf, pos, n);
	case 'char8'
		[v,pos] = decChar8(buf, pos, n);
	case 'char'
		[v,pos] = decChar(buf, pos, n);
	case 'cell'
		[v,pos] = decCell(buf, pos, n);
	case 'struct'
		[v,pos] = decStruct(buf, pos, n);
	case 'sparse'
		[v,pos] = decSparse(buf, pos, n);
	case 'complex'
		[v,pos] = decComplex(buf, pos, n);
	otherwise
		[v,pos] = decNumeric(buf, pos, n*bpe, cls);
	end
	if pos <= numel(buf)
		v = reshape(v, vsz);
	end
end

function [v,pos] = decNumeric(buf, pos, n, cls)
	if ~isempty(cls)
		[i,j,pos] = consume(buf, pos, n);
		v = typecast(buf(i:j), cls);
	else
		v = [];
	end
end

function [v,pos] = decComplex(buf, pos, n)
	[cls,bpe,~,pos] = decTag(buf, pos);
	n = n*bpe;
	[re,pos] = decNumeric(buf, pos, n, cls);
	[im,pos] = decNumeric(buf, pos, n, cls);
	v = complex(re, im);
end

function [v,pos] = decLogical(buf, pos, n)
	[i,j,pos] = consume(buf, pos, n);
	v = logical(buf(i:j));
end

function [v,pos] = decSparse(buf, pos, n)
	[idx,pos] = decNext(buf, pos);
	[nzv,pos] = decNext(buf, pos);
	if coder.target('MATLAB')
		v = sparse(double(idx), 1, nzv, double(n), 1);
	else
		v = zeros(n, 1, class(nzv));
		v(idx) = nzv;
	end
end

function [v,pos] = decChar8(buf, pos, n)
	[i,j,pos] = consume(buf, pos, n);
	v = char(buf(i:j));
end

function [v,pos] = decChar(buf, pos, n)
	[v,pos] = decNumeric(buf, pos, n*2, 'uint16');
	v = char(v);
end

function [v,pos] = decCell(buf, pos, n)
	v = cell(n, 1);
	for i = 1:n
		[v{i},pos] = decNext(buf, pos);
	end
end

function [v,pos] = decStruct(buf, pos, n)
	[nf,pos] = decNumeric(buf, pos, uint32(2), 'uint16');
	fieldvals = cell(1, 2*nf);
	for i = 1:2:numel(fieldvals)
		[fieldvals{i},pos] = decNext(buf, pos);
		vals = cell(n, 1);
		for j = 1:n
			[vals{j},pos] = decNext(buf, pos);
		end
		fieldvals{i+1} = vals;
	end
	v = struct(fieldvals{:});
end

function [cls,bpe,vsz,pos] = decTag(buf, pos)
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
		[vsz,pos] = decNumeric(buf, pos, szn, fmt{szf});
		vsz = uint32(vsz');
	end
	classes = {'double','single','logical','char','char8','cell','struct', ...
			'int8','uint8','int16','uint16','int32','uint32','int64', ...
			'uint64','sparse','complex'};
	bytesPerElement = uint32([8,4,1,2,1,0,0,1,1,2,2,4,4,8,8,0,0]);
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
	if isempty(j) || j >= numel(buf)
		i = uint32(1);
		j = uint32(0);
		pos = intmax('uint32');
	end
end
