%MXDECODE   Deserialize data from a byte array.
%
%   V = MXDECODE(BUF) decodes the original value V from uint8 column vector BUF.
%
%   V = MXDECODE(BUF,SIG) uses the specified SIG to validate BUF and determine
%     the correct byte order for decoding.
%
%   [V,ERR] = MXDECODE(BUF,SIG,V) activates standalone mode for generating C/C++
%     code. The id of any error encountered during decoding is returned in ERR.
%     The same V must be used for input and output. An error is returned if BUF
%     does not contain a valid encoding of V. In other words, V specifies the
%     required BUF format and BUF provides the data.
%
%   [V,ERR] = MXDECODE(BUF,SIG,V,UBOUND) uses the specified UBOUND as the upper
%     bound on the number of elements or struct fields that may be decoded for
%     any value in BUF. Failure to use identical UBOUND for all MXDECODE calls
%     within the same program will result in the following error: "The name
%     'MxDecCtx' has already been defined using a different type." The default
%     is Inf.
%
%   The following paragraphs apply only to standalone mode:
%
%   All non-scalar values in V, including V itself, must be declared as
%   variable-size using coder.varsize. Scalar values must not be declared as
%   such. You may specify an explicit upper bound for varying dimensions, but
%   you may not use the dims argument to coder.varsize and you may not modify V
%   between coder.varsize declarations and the call to MXDECODE. In general,
%   your program should follow this pattern:
%
%     function [buf,out1,out2,...,outN] = compute(buf, in1, in2, ..., inN)
%         state = struct( ...
%             'scalar', 123, ...  % Must not be declared with coder.varsize
%             'rowvec', '', ...
%             'colvec', reshape([], 0, 1), ...
%             'matrix', [], ...
%             'cell',   {'',''} ...  % Cells may not be empty
%         );
%
%         % Declare all variable-size fields
%         coder.varsize('state.rowvec', 'state.colvec', 'state.mat', ...
%                       'state.cell');
%
%         % Decode previous state
%         [state,err] = mxdecode(buf, [], state);
%         if ~isempty(err)
%             % Depending on what the error is, state may be partially decoded.
%             % You should either reset it to its original value or perform
%             % sanity checks on the decoded data.
%         end
%
%         % Perform your computation here, updating state as needed
%
%         % Encode state for the next iteration
%         buf = mxencode(state, '', [], true);
%     end
%
%   Only 2D arrays are supported. Any dimensions in BUF beyond the first two are
%   collapsed into the second one.
%
%   Sparse and 16-bit Unicode char arrays are not supported (Coder restrictions
%   as of R2016b).
%
%   Heterogeneous cells are not supported as they offer no advantages over
%   structs. Structs and homogeneous cells must contain at least one element
%   which determines the type of data that can be assigned to each field/cell.
%   Variable-size structs and cells must contain at least two elements to be
%   correctly declared as such using the default coder.varsize dims logic.
%
%   Struct decoding is considered successful if at least one of the fields in V
%   and BUF match. Fields in V that are not in BUF are ignored. Fields in BUF
%   that are not in V are skipped. This allows struct layout to be modified and
%   still be decoded from an old-layout BUF.
%
%   "Dimension N is fixed on the left-hand side but varies on the right" and
%   similar errors are most likely due to incorrect coder.varsize declarations.
%   The decoder considers any dimension for which size(v,dim) ~= 1 as varying,
%   which is the same heuristic used by coder.varsize without an explicit dims
%   argument. Certain empty arrays, such as '', have size 1x0 by default, and
%   are considered row vectors by coder.varsize. You must reshape them to 0x1 or
%   0x0 to change the varying dimension(s).
%
%   See also MXENCODE, CODER.VARSIZE.

%   Written by Maxim Khitrov (February 2017)

function [v,err] = mxdecode(buf, sig, v, ubound)  %#codegen
	narginchk(1, 4);
	cgen = int32(nargin >= 3);
	if nargin < 4
		ubound = Inf;
	end
	ctx = struct( ...
		'buf',    buf, ...
		'pos',    int32(3), ...
		'swap',   false, ...
		'cgen',   false(1 - cgen), ...          % Empty is compile-time true
		'ubound', zeros(int32(ubound), 0), ...  % Size is compile-time constant
		'err',    '' ...
	);
	if cgen
		coder.cstructname(ctx, 'MxDecCtx');
		coder.varsize('ctx.err', [1,32]);
	else
		v = [];
	end
	n = int32(numel(buf));
	if n == 0 || bitand(n,3) ~= 0 || ~isa(buf,'uint8') || ~isreal(buf) || ...
			~iscolumn(buf) || buf(1) == buf(2)
		ctx = fail(ctx, 'invalidBuf', 'invalid buffer');
		err = ctx.err;
		return;
	end
	if nargin >= 2 && ~isempty(sig)
		sig = uint16(sig);
	else
		sig = uint16(42);
	end
	switch typecast(buf(1:2), 'uint16')
	case sig
	case swapbytes(sig)
		ctx.swap = true;
	otherwise
		ctx = fail(ctx, 'invalidSig', 'invalid signature');
		err = ctx.err;
		return;
	end
	[ctx,v] = decNext(ctx, v);
	pad = int32(bitcmp(buf(n)));
	if ~pad || pad > 4 || ctx.pos+pad-1 ~= n || any(buf(ctx.pos:n-1) ~= buf(n))
		ctx = fail(ctx, 'invalidPad', 'invalid buffer padding');
	end
	err = ctx.err;
end

function [ctx,v] = decNext(ctx, v)
	[ctx,cid,vsz] = decTag(ctx);
	% Non-generated code returns what is actually in the buffer. Generated code
	% uses v to guide the decoding process while verifying that the buffer
	% contains a valid encoding of v.
	if ~ctx.cgen
		n = prod(vsz, 'native');
		switch cid2cls(cid)
		case 'logical'
			[ctx,v] = decLogical(ctx, [], n);
		case {'char8','char16'}
			[ctx,v] = decChar(ctx, [], n, cid);
		case 'cell'
			[ctx,v] = decCell(ctx, [], n);
		case 'struct'
			[ctx,v] = decStruct(ctx, [], n);
		case 'sparse'
			[ctx,v] = decSparse(ctx, n);
		case 'complex'
			[ctx,v] = decComplex(ctx, [], n);
		case ''
		otherwise
			[ctx,v] = decNumeric(ctx, [], n, cid);
		end
		if valid(ctx)
			% TODO: Verify that numel(v) == n
			v = reshape(v, vsz);
		else
			v = [];
		end
		return;
	end
	n = vsz(1) * vsz(2);
	if n > ubound(ctx)
		ctx = fail(ctx, 'ubound', 'number of elements exceeds ubound');
		return;
	end
	coder.varsize('tmp', [ubound(ctx),1], [true,false]);
	if isnumeric(v) && isreal(v)
		[ctx,tmp] = decNumeric(ctx, v, n, cid);
	elseif isnumeric(v) && ~isreal(v) && cid == cls2cid('complex')
		[ctx,tmp] = decComplex(ctx, v, n);
	elseif islogical(v) && cid == cls2cid('logical')
		[ctx,tmp] = decLogical(ctx, v, n);
	elseif ischar(v) && (cid == cls2cid('char8') || cid == cls2cid('char16'))
		[ctx,tmp] = decChar(ctx, v, n, cid);
	elseif iscell(v) && cid == cls2cid('cell')
		[ctx,tmp] = decCell(ctx, v, n);
	elseif isstruct(v) && cid == cls2cid('struct')
		[ctx,tmp] = decStruct(ctx, v, n);
	else
		ctx = classMismatch(ctx);
		return;
	end
	if valid(ctx)
		if isscalar(v)  %size(v,1) == 1 && size(v,2) == 1
			if ~isscalar(tmp)
				ctx = fail(ctx, 'nonScalar', 'decoded value is not a scalar');
			elseif iscell(v)
				v{1} = tmp{1};
			else
				v(1) = tmp(1);
			end
		elseif size(v,1) ~= 1 && size(v,2) == 1
			v = tmp;
		elseif size(v,1) == 1 && size(v,2) ~= 1
			v = reshape(tmp, 1, numel(tmp));
		elseif size(v,1) ~= 1 && size(v,2) ~= 1  % Coder unhappy with an else
			v = reshape(tmp, vsz(1), vsz(2));
		end
	end
end

function [ctx,v] = decNumeric(ctx, v, n, cid)
	bytesPerElement = int32([8,4,0,0,0,0,0,1,1,2,2,4,4,8,8]);
	if cid < 1 || numel(bytesPerElement) < cid || ~bytesPerElement(cid)
		ctx = fail(ctx, 'invalidNumeric', 'invalid numeric encoding');
		v = reshape(v, numel(v), 1);
		return;
	end
	[ctx,i,j] = consume(ctx, n*bytesPerElement(cid));
	if ~ctx.cgen
		v = typecast(ctx.buf(i:j), cid2cls(cid));
	elseif cid == cls2cid(class(v))
		v = typecast(ctx.buf(i:j), class(v));
	else
		ctx = classMismatch(ctx);
		v = reshape(v, numel(v), 1);
	end
	if ctx.swap
		v = swapbytes(v);
	end
end

function [ctx,v] = decComplex(ctx, v, n)
	[ctx,cid] = decTag(ctx);
	[ctx,re] = decNumeric(ctx, real(v(:)), n, cid);
	[ctx,im] = decNumeric(ctx, imag(v(:)), n, cid);
	v = complex(re, im);
end

function [ctx,v] = decLogical(ctx, v, n)
	[ctx,i,j] = consume(ctx, n);
	v = logical(ctx.buf(i:j));
end

function [ctx,v] = decSparse(ctx, n)
	[ctx,idx] = decNext(ctx, []);
	[ctx,nze] = decNext(ctx, []);
	v = sparse(double(idx), 1, nze, double(n), 1);
end

function [ctx,v] = decChar(ctx, v, n, cid)
	if cid == cls2cid('char8')
		[ctx,i,j] = consume(ctx, n);
		v = char(ctx.buf(i:j));
		v = reshape(v, numel(v), 1);
	elseif ~ctx.cgen
		u16 = zeros(0, 1, 'uint16');
		[ctx,u16] = decNumeric(ctx, u16, n, cls2cid('uint16'));
		v = char(u16);
	else
		ctx = fail(ctx, 'unicodeChar', '16-bit characters are not supported');
		v = reshape(v, numel(v), 1);
	end
end

function [ctx,out] = decCell(ctx, v, n)
	if ~ctx.cgen
		e = [];
	elseif isempty(v)
		% At least one element is required to know the type of the cell
		ctx = fail(ctx, 'emptyCell', 'cell does not contain any elements');
		out = reshape(v, numel(v), 1);
		return;
	else
		e = v{1};
	end
	out = cell(n, 1);
	for i = 1:numel(out)
		[ctx,out{i}] = decNext(ctx, e);
	end
end

function [ctx,out] = decStruct(ctx, v, n)
	if ~ctx.cgen
		[ctx,fields] = decNext(ctx, []);
		if ~iscell(fields)
			ctx = fail(ctx, 'invalidStruct', 'struct field names missing');
			fields = {};
		end
		if isempty(fields)
			out = repmat(struct(), n, 1);
			return;
		end
		fieldvals = cell(1, 2*numel(fields));
		fieldvals(1:2:numel(fieldvals)) = fields;
		for i = 2:2:numel(fieldvals)
			vals = cell(n, 1);
			for j = 1:n
				[ctx,vals{j}] = decNext(ctx, []);
			end
			fieldvals{i} = vals;
		end
		out = struct(fieldvals{:});
		return;
	end
	vfields = fieldnames(v);
	bfields = {'';''};
	coder.varsize('bfields', [ubound(ctx),1]);
	coder.varsize('bfields{:}', [1,63]);  % namelengthmax
	[ctx,bfields] = decNext(ctx, bfields);
	if valid(ctx) && ~(numel(vfields) == numel(bfields) && ...
			all(strcmp(vfields, bfields)))
		ctx = fail(ctx, 'invalidStruct', 'struct field mismatch');
	end
	if ~valid(ctx)
		out = reshape(v, numel(v), 1);
		return;
	end
	% TODO: Handle extra or missing fields
	out = repmat(v(1), n, 1);
	for i = 1:numel(vfields)
		for j = 1:n
			[ctx,out(j).(vfields{i})] = decNext(ctx, v(1).(vfields{i}));
		end
	end
end

function [ctx,cid,vsz] = decTag(ctx)
	[ctx,i,~] = consume(ctx, int32(1));
	% Black magic to prevent Coder from delaying the evaluation of cid and fmt.
	% Without bitand, Coder decides to make a copy of the entire ctx.buf and use
	% it to evaluate cid/fmt later from the original ctx.buf (even thought there
	% is no code path that can possibly change it). Verify that the function
	% emxCopyStruct_MxDecCtx does not exist in the generated code after making
	% any changes here.
	cid = bitand(int32(bitand(ctx.buf(i), 31)), 255);
	fmt = bitand(int32(bitshift(ctx.buf(i), -5)), 255);
	if cid < 1 || 17 < cid
		ctx = fail(ctx, 'invalidTag', 'tag specifies an unknown class');
	end
	vsz = ones(1, 2, 'int32');
	switch fmt
	case 0
	case {1,2}
		[ctx,i,~] = consume(ctx, int32(1));
		vsz(fmt) = ctx.buf(i);
	case 3
		[ctx,i,~] = consume(ctx, int32(2));
		vsz(:) = ctx.buf(i:i+1);
	case 4
		vsz(:) = 0;
	otherwise
		[ctx,i,~] = consume(ctx, int32(1));
		szn = bitand(int32(ctx.buf(i)), 255);  % More black magic
		if szn >= 2
			if isempty(ctx.cgen)
				%coder.varsize('u16', 'u32', 'i32', [255,1]);
			end
			switch bitand(fmt, 3)
			case 1
				[ctx,i,j] = consume(ctx, szn);
				i32 = int32(ctx.buf(i:j));
			case 2
				u16 = zeros(0, 1, 'uint16');
				[ctx,u16] = decNumeric(ctx, u16, szn, cls2cid('uint16'));
				i32 = int32(u16);
			otherwise
				u32 = zeros(0, 1, 'uint32');
				[ctx,u32] = decNumeric(ctx, u32, szn, cls2cid('uint32'));
				i32 = int32(u32);
			end
			if ~ctx.cgen
				vsz = i32';
			else
				vsz(1) = i32(1);
				vsz(2) = prod(i32(2:end), 'native');
			end
		else
			ctx = fail(ctx, 'invalidNdims', 'invalid number of dimensions');
		end
	end
	if ~valid(ctx)
		cid = int32(0);
		vsz = zeros(1, 2, 'int32');
	end
end

function [ctx,i,j] = consume(ctx, n)
	i = ctx.pos;
	j = ctx.pos + n - 1;
	ctx.pos = ctx.pos + n;
	if isempty(j) || j >= numel(ctx.buf)
		ctx = fail(ctx, 'invalidBuf', 'invalid buffer format');
		i = int32(1);
		j = int32(0);
	end
end

function ctx = classMismatch(ctx)
	ctx = fail(ctx, 'classMismatch', 'encoding does not match expected class');
end

function ctx = fail(ctx, id, msg)
	if ~ctx.cgen
		error([mfilename ':' id], msg);
	elseif isempty(ctx.err)
		ctx.pos = intmax;
		ctx.err = id;
		disp(msg);
	end
end

function tf = valid(ctx)
	tf = (ctx.pos < intmax);
end

function ub = ubound(ctx)
	ub = double(size(ctx.ubound, 1));
	if ub == intmax
		ub = Inf;
	end
end

function cid = cls2cid(cls)
	cid = int32(0);
	switch cls
	case 'double';  cid = int32(1);
	case 'single';  cid = int32(2);
	case 'logical'; cid = int32(3);
	case 'char8';   cid = int32(4);
	case 'char16';  cid = int32(5);
	case 'cell';    cid = int32(6);
	case 'struct';  cid = int32(7);
	case 'int8';    cid = int32(8);
	case 'uint8';   cid = int32(9);
	case 'int16';   cid = int32(10);
	case 'uint16';  cid = int32(11);
	case 'int32';   cid = int32(12);
	case 'uint32';  cid = int32(13);
	case 'int64';   cid = int32(14);
	case 'uint64';  cid = int32(15);
	case 'sparse';  cid = int32(16);
	case 'complex'; cid = int32(17);
	end
end

function cls = cid2cls(cid)
	cls = '';
	switch cid
	case 1;  cls = 'double';
	case 2;  cls = 'single';
	case 3;  cls = 'logical';
	case 4;  cls = 'char8';
	case 5;  cls = 'char16';
	case 6;  cls = 'cell';
	case 7;  cls = 'struct';
	case 8;  cls = 'int8';
	case 9;  cls = 'uint8';
	case 10; cls = 'int16';
	case 11; cls = 'uint16';
	case 12; cls = 'int32';
	case 13; cls = 'uint32';
	case 14; cls = 'int64';
	case 15; cls = 'uint64';
	case 16; cls = 'sparse';
	case 17; cls = 'complex';
	end
end

function bpe = cid2bpe2(cid)
	bpe = int32(0);
	switch cid
	case 1;    bpe = int32(8);
	case 2;    bpe = int32(4);
	case 3;    bpe = int32(1);
	case 4;    bpe = int32(1);
	case 5;    bpe = int32(2);
	case 6;
	case 7;
	case 8;    bpe = int32(1);
	case 9;    bpe = int32(1);
	case 10;   bpe = int32(2);
	case 11;   bpe = int32(2);
	case 12;   bpe = int32(4);
	case 13;   bpe = int32(4);
	case 14;   bpe = int32(8);
	case 15;   bpe = int32(8);
	case 16;
	case 17;
	end
end
