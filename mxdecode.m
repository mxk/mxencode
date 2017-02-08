%MXDECODE   Deserialize data from a byte array.
%
%   V = MXDECODE(BUF) decodes the original value V from uint8 column vector BUF.
%
%   V = MXDECODE(BUF,SIG) uses the specified SIG to validate buffer signature.
%     If SIG is not the same value that was provided to MXENCODE, decoding fails
%     with 'mxdecode:invalidSig' error.
%
%   [V,ERR] = MXDECODE(BUF,SIG,V) activates standalone mode for generating C/C++
%     code with MATLAB Coder. If an error is encountered during decoding, ERR
%     will contain its message id and V may be partially modified. The same V
%     must be used for input and output. An error is returned if BUF does not
%     contain a valid encoding of V. In other words, V specifies the required
%     BUF format and BUF provides the data.
%
%   [V,ERR] = MXDECODE(BUF,SIG,V,UBOUND) uses UBOUND as the upper bound on the
%     number of elements and struct fields for any value in BUF to generate more
%     efficient code. You must use the same UBOUND for all MXDECODE calls within
%     the same program or you'll get the following error: "The name 'MxDecCtx'
%     has already been defined using a different type." The default is Inf.
%
%   The paragraphs below apply only to standalone mode:
%
%   All non-scalar values in V, including V itself, must be declared as
%   variable-size using CODER.VARSIZE. Scalar values must not be declared as
%   such. You may specify an explicit upper bound for varying dimensions, but
%   you may not use the dims argument to CODER.VARSIZE and you may not modify V
%   between CODER.VARSIZE declarations and the call to MXDECODE. In general,
%   your program should have the following structure:
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
%         coder.varsize('state.rowvec', 'state.colvec', 'state.matrix', ...
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
%         [buf,~] = mxencode(state);
%     end
%
%   Only 2-D arrays are supported. Any dimensions in BUF beyond the first two
%   are collapsed into the second one.
%
%   Sparse and 16-bit Unicode char arrays are not supported (Coder restrictions
%   as of R2016b).
%
%   Heterogeneous cells are not supported as they offer no advantages over
%   structs. Structs and homogeneous cells must contain at least one element
%   which determines the type of data that can be assigned to each field/cell.
%   Variable-size structs and cells must contain at least two elements to be
%   correctly declared as such using the default CODER.VARSIZE dims logic.
%
%   Struct decoding is considered successful if V has no fields or if at least
%   one of the fields in V and BUF match using strcmp. Fields in V that are not
%   in BUF are ignored. Fields in BUF that are not in V are skipped. This allows
%   struct layout to be modified and still be decoded from an old-layout BUF.
%
%   "Dimension N is fixed on the left-hand side but varies on the right" and
%   similar errors are most likely due to incorrect CODER.VARSIZE declarations.
%   The decoder considers any dimension for which size(v,dim) ~= 1 as varying,
%   which is the same heuristic used by CODER.VARSIZE without an explicit dims
%   argument. Certain empty arrays, such as '', have size 1x0 by default, and
%   are considered row vectors by CODER.VARSIZE. You must reshape them to 0x1 or
%   0x0 to change the varying dimension(s).
%
%   See also MXENCODE, CODER.VARSIZE.

%   Written by Maxim Khitrov (February 2017)

function [v,err] = mxdecode(buf, sig, v, ubound)  %#codegen
	cgen = int32(nargout == 2);
	if cgen
		narginchk(3, 4);
	else
		narginchk(1, 2);
		v = [];
	end
	if nargin < 4
		ubound = Inf;
	end
	ctx = struct( ...
		'buf',    zeros(0, 1, 'uint8'), ...
		'pos',    int32(3), ...
		'swap',   false, ...
		'cgen',   false(1 - cgen), ...          % Empty is compile-time true
		'ubound', zeros(int32(ubound), 0), ...  % Size is compile-time constant
		'err',    '' ...
	);
	if cgen
		coder.cstructname(ctx, 'MxDecCtx');
		coder.varsize('ctx.buf');
		coder.varsize('ctx.err', [1,32]);
	end

	% Check buf size and format
	n = int32(numel(buf));
	if ~n || bitand(n,3) || ~isa(buf,'uint8') || ~isreal(buf) || ~iscolumn(buf)
		ctx = fail(ctx, 'invalidBuf');
		err = ctx.err;
		return;
	end
	pad = int32(bitcmp(buf(n)));
	if cgen && ~coder.target('MATLAB')
		% Black magic to force the evaluation of n and pad here. Coder has an
		% annoying habit of delaying or inlining such evaluations in generated
		% code, even when the resulting code is (much!) slower. In the worst
		% case, it copies buf to keep an "old" version around for such delayed
		% evaluations (even though buf is never modified). Verify that the
		% function 'emxCopyStruct_MxDecCtx' does not exist in the generated code
		% after making any changes and look for other buf copies as well (b_buf,
		% c_buf, ctx_buf, etc.).
		coder.ceval('(void)', coder.ref(n), coder.ref(pad));
	end
	if ~pad || pad > 4 || any(buf(n-pad+1:n-1) ~= buf(n))
		ctx = fail(ctx, 'invalidPad');
		err = ctx.err;
		return;
	end

	% Verify signature and detect byte order
	fver = uint16(240);
	usig = uint16(42);
	if nargin >= 2 && ~isempty(sig)
		usig = uint16(sig);
	end
	if usig >= 240 || ~((buf(1) == usig && buf(2) == fver) || ...
			(buf(1) == fver && buf(2) == usig))
		ctx = fail(ctx, 'invalidSig');
		err = ctx.err;
		return;
	end
	ctx.swap = (typecast(buf(1:2),'uint16') ~= bitshift(fver,8)+usig);

	% Decode
	ctx.buf = buf;
	[ctx,v] = decNext(ctx, v);
	if ctx.pos ~= n - pad + 1
		ctx = fail(ctx, 'invalidBuf');
	end
	err = ctx.err;
end

function [ctx,v] = decNext(ctx, v)
	[ctx,cid,vsz] = decTag(ctx);
	n = prod(vsz, 'native');
	% Non-generated code returns what is actually in the buffer. Generated code
	% uses v to guide the decoding process while verifying that the buffer
	% contains a valid encoding of v.
	if ~ctx.cgen
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
	if n > ubound(ctx)
		ctx = fail(ctx, 'ubound');
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
		ctx = fail(ctx, 'classMismatch');
		return;
	end
	if valid(ctx)
		if isscalar(v)
			if ~isscalar(tmp)
				ctx = fail(ctx, 'nonScalar');
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
			v = reshape(tmp, vsz);
		end
	end
end

function [ctx,v] = decNumeric(ctx, v, n, cid)
	bpe = cid2bpe(cid);
	if bpe == 0 || cid > cls2cid('uint64')
		ctx = fail(ctx, 'notNumeric');
		v = reshape(v, numel(v), 1);
		return;
	end
	[ctx,i,j] = consume(ctx, n*bpe);
	if ~ctx.cgen
		v = typecast(ctx.buf(i:j), cid2cls(cid));
	elseif cid == cls2cid(class(v))
		v = typecast(ctx.buf(i:j), class(v));
	else
		ctx = fail(ctx, 'classMismatch');
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
		ctx = fail(ctx, 'unicodeChar');
		v = reshape(v, numel(v), 1);
	end
end

function [ctx,out] = decCell(ctx, v, n)
	if ~ctx.cgen
		e = [];
	elseif isempty(v)
		% At least one element is required to know the type of the cell
		ctx = fail(ctx, 'emptyCell');
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

	% Get actual and encoded fields
	vfields = fieldnames(v);
	bfields = {'';''};
	coder.varsize('bfields', [ubound(ctx),1]);
	coder.varsize('bfields{:}', [1,63]);  % namelengthmax
	[ctx,bfields] = decNext(ctx, bfields);
	out = repmat(v(1), n, 1);
	err = ~isempty(vfields);

	% Decode data for matching fields, ignore struct fields that weren't
	% encoded, skip encoded fields that aren't in the struct. At least one field
	% must match. Field order may be different.
	for i = 1:numel(bfields)
		field = bfields{i};
		match = false;

		% Must use this form to make vfields{j} a compile-time constant
		for j = 1:numel(vfields)
			if ~strcmp(vfields{j}, field)
				continue;
			end
			match = true;
			err = false;
			for k = 1:n
				[ctx,out(k).(vfields{j})] = decNext(ctx, v(1).(vfields{j}));
			end
			break;
		end
		if ~match
			for k = 1:n
				ctx = skip(ctx, []);
			end
		end
	end
	if valid(ctx) && err
		ctx = fail(ctx, 'invalidStruct');
	end
end

function [ctx,n] = skip(ctx, expect)
	[ctx,cid,vsz] = decTag(ctx);
	n = prod(vsz, 'native');
	if ~isempty(expect) && ~any(cid == expect)
		ctx = fail(ctx, 'invalidBuf');
		return;
	end
	bpe = cid2bpe(cid);
	if bpe > 0
		ctx = consume(ctx, n*bpe);
		return;
	end
	switch cid
	case cls2cid('cell')
		for i = 1:n
			ctx = skip(ctx, []);
		end
	case cls2cid('struct')
		[ctx,nf] = skip(ctx, cls2cid('cell'));
		for i = 1:nf*n
			ctx = skip(ctx, []);
		end
	case cls2cid('sparse')
		ctx = skip(ctx, [cls2cid('uint8'),cls2cid('uint16'),cls2cid('uint32')]);
		ctx = skip(ctx, [cls2cid('double'),cls2cid('logical')]);
	case cls2cid('complex')
		[ctx,cid,~] = decTag(ctx);
		ctx = consume(ctx, 2*n*cid2bpe(cid));
	end
end

function [ctx,cid,vsz] = decTag(ctx)
	[ctx,i,~] = consume(ctx, int32(1));
	cid = bitand(ctx.buf(i), 31);
	fmt = bitshift(ctx.buf(i), -5);
	if isempty(ctx.cgen) && ~coder.target('MATLAB')
		coder.ceval('(void)', coder.ref(cid), coder.ref(fmt));
	end
	if cid < 1 || 17 < cid
		ctx = fail(ctx, 'invalidTag');
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
		szn = int32(ctx.buf(i));
		if isempty(ctx.cgen) && ~coder.target('MATLAB')
			coder.ceval('(void)', coder.ref(szn));
			coder.varsize('u16', 'u32', 'i32', [255,1]);
		end
		if szn >= 2
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
			ctx = fail(ctx, 'invalidNdims');
		end
	end
	if ~valid(ctx)
		cid = uint8(0);
		vsz = zeros(1, 2, 'int32');
	end
end

function [ctx,i,j] = consume(ctx, n)
	i = ctx.pos;
	j = ctx.pos + n - 1;
	ctx.pos = ctx.pos + n;
	if isempty(j) || j >= numel(ctx.buf)
		ctx = fail(ctx, 'invalidBuf');
		i = int32(1);
		j = int32(0);
	end
end

function ub = ubound(ctx)
	ub = double(size(ctx.ubound, 1));
	if ub == intmax
		ub = Inf;
	end
end

function tf = valid(ctx)
	tf = (ctx.pos < intmax);
end

function ctx = fail(ctx, id)
	if isempty(ctx.err)
		ctx.err = id;
		ctx.pos = intmax;
	end
	switch id
	case 'classMismatch'
		msg = 'Encoding does not match expected class.';
	case 'invalidBuf'
		msg = 'Invalid buffer format.';
	case 'invalidNdims'
		msg = 'Invalid number of dimensions.';
	case 'invalidSig'
		msg = 'Invalid buffer signature.';
	case 'invalidPad'
		msg = 'Invalid buffer padding.';
	case 'ubound'
		msg = 'Number of elements exceeds ubound.';
	case 'nonScalar'
		msg = 'Decoded value is not a scalar.';
	case 'notNumeric'
		msg = 'Encoded class is not numeric.';
	case 'unicodeChar'
		msg = '16-bit characters are not supported.';
	case 'emptyCell'
		msg = 'Cell does not contain any elements.';
	case 'invalidStruct'
		msg = 'Invalid struct or field name mismatch.';
	case 'invalidTag'
		msg = 'Tag specifies an unknown class.';
	otherwise
		msg = 'Unknown error.';
	end
	if ~isempty(ctx.cgen) || coder.target('MEX')
		error([mfilename ':' id], msg);
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

function cls = cid2cls(cid)
	cls = '';
	switch cid
	case 1;  cls = 'double';
	case 2;  cls = 'single';
	case 3;  cls = 'int8';
	case 4;  cls = 'uint8';
	case 5;  cls = 'int16';
	case 6;  cls = 'uint16';
	case 7;  cls = 'int32';
	case 8;  cls = 'uint32';
	case 9;  cls = 'int64';
	case 10; cls = 'uint64';
	case 11; cls = 'logical';
	case 12; cls = 'char8';
	case 13; cls = 'char16';
	case 14; cls = 'cell';
	case 15; cls = 'struct';
	case 16; cls = 'sparse';
	case 17; cls = 'complex';
	end
end

function bpe = cid2bpe(cid)
	bytesPerElement = int8([8,4,1,1,2,2,4,4,8,8,1,1,2]);
	if 1 <= cid && cid <= numel(bytesPerElement)
		bpe = int32(bytesPerElement(cid));
	else
		bpe = int32(0);
	end
end
