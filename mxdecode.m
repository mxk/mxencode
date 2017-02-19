%MXDECODE   Deserialize data from a byte array.
%
%   V = MXDECODE(BUF) decodes the original value V from uint8 column vector BUF.
%
%   V = MXDECODE(BUF,SIG) uses the specified SIG to validate buffer signature.
%     If SIG is not the same value that was provided to MXENCODE, decoding fails
%     with 'invalidSig' error.
%
%   [V,ERR] = MXDECODE(BUF,SIG,V) activates standalone mode for generating C/C++
%     code with MATLAB Coder (requires R2016b+). If an error is encountered
%     during decoding, ERR will contain its message id (just the mnemonic) and V
%     may be partially modified. The same V should be used for input and output.
%     An error is returned if BUF does not contain a valid encoding of V. In
%     other words, V specifies the required BUF format and BUF provides the
%     data.
%
%   [V,ERR] = MXDECODE(BUF,SIG,V,UBOUND) uses UBOUND as the upper bound on the
%     number of elements, struct fields, and field name lengths for any value in
%     BUF. This allows Coder to generate more efficient code. If UBOUND is a 1x2
%     vector, the first bound applies to all numeric and logical data, and the
%     second to char arrays, cells, and structs. If UBOUND is a scalar, the same
%     bound is used for both categories. Decoding fails with 'numelLimit' error
%     if BUF or V violate this limit. You must use the same constant UBOUND for
%     all MXDECODE calls within the same program or you'll get the following
%     error: "The name 'MxDecCtx' has already been defined using a different
%     type." The default is [4096,128].
%
%   The paragraphs below apply only to standalone mode:
%
%   MXENCODE and MXDECODE assume coder.CodeConfig.SaturateOnIntegerOverflow is
%   set to 'true' to match MATLAB behavior.
%
%   All non-scalar values in V, including V itself, must be declared as
%   variable-size using CODER.VARSIZE. Scalar values must not be declared as
%   such. You may specify an explicit upper bound for varying dimensions, but
%   the decoder cannot enforce it if it's smaller than the UBOUND argument. You
%   may not use the dims argument to CODER.VARSIZE and you may not modify V
%   between CODER.VARSIZE declarations and the call to MXDECODE. In general,
%   your program should have the following structure:
%
%     function [buf,err,out1,out2,...,outN] = compute(buf, in1, in2, ..., inN)
%         state = struct( ...
%             'scalar', 123, ...  % Must not be declared with coder.varsize
%             'rowvec', '', ...
%             'colvec', reshape([], 0, 1), ...
%             'matrix', [], ...
%             'cell',   {'',''} ...  % Cells may not be empty
%         );
%
%         % Declare all variable-size fields (specify upper bounds, if possible)
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
%         % Encode state for the next run
%         [buf,err] = mxencode(state);
%     end
%
%   Only 2-D arrays are supported. This is enforced at compile time by the
%   encoder and run time by the decoder. Sparse and 16-bit Unicode char arrays
%   are not supported (Coder restrictions as of R2016b).
%
%   Heterogeneous cells are not supported as they offer no advantages over
%   structs. Structs and homogeneous cells must contain at least one element
%   which determines the type of data that can be assigned to each field/cell.
%   As a result, variable-size structs and cells must contain at least two
%   elements to be correctly declared as such using the default CODER.VARSIZE
%   dims logic.
%
%   Struct decoding is considered successful if V has no fields or if at least
%   one of the fields in V and BUF match via strcmp. Fields in V that are not in
%   BUF are ignored. Fields in BUF that are not in V are skipped. This allows
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
	cgen = (nargout == 2);
	if cgen
		narginchk(3, 4);
	else
		narginchk(1, 2);
		v = [];
	end
	if nargin < 4 || isempty(ubound) || numel(ubound) > 2
		ub = [4096,128];
	elseif isscalar(ubound)
		ub = [ubound(1),ubound(1)];
	else
		ub = reshape(ubound, 1, 2);
	end
	ctx = struct( ...
		'pos',    int32(3), ...
		'len',    int32(0), ...
		'swap',   false, ...
		'cgen',   false(int32(~cgen)), ...   % Empty is compile-time true
		'ubound', zeros(int32([ub,0])), ...  % Size is compile-time constant
		'err',    '' ...
	);
	if cgen
		coder.cstructname(ctx, 'MxDecCtx');
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
	if ~pad || pad > 4 || any(buf(n-pad+1:n-1) ~= buf(n))
		ctx = fail(ctx, 'invalidPad');
		err = ctx.err;
		return;
	end

	% Verify signature and detect byte order
	fmt = uint16(240);
	usr = uint16(42);
	if nargin >= 2 && ~isempty(sig)
		usr = uint16(sig);
	end
	if usr >= 240 || ~((buf(1) == usr && buf(2) == fmt) || ...
			(buf(1) == fmt && buf(2) == usr))
		ctx = fail(ctx, 'invalidSig');
		err = ctx.err;
		return;
	end
	ctx.swap = (typecast(buf(1:2),'uint16') ~= bitshift(fmt,8)+usr);

	% Decode
	ctx.len = n;
	[ctx,v] = decNext(ctx, buf, v);
	if ctx.pos ~= n - pad + 1
		ctx = fail(ctx, 'corruptBuf');
	end
	err = ctx.err;
end

function [ctx,v] = decNext(ctx, buf, v)
	[ctx,cid,vsz,n] = decTag(ctx, buf);
	if ~isempty(ctx.err)
		return;
	end

	% Interpreted code returns what is actually in the buffer
	if ~ctx.cgen
		switch cid2cls(cid)
		case 'logical'
			[ctx,v] = decLogical(ctx, buf, v, n);
		case {'char8','char16'}
			[ctx,v] = decChar(ctx, buf, v, n, cid);
		case 'cell'
			[ctx,v] = decCell(ctx, buf, v, n);
		case 'struct'
			[ctx,v] = decStruct(ctx, buf, v, n);
		case 'sparse'
			[ctx,v] = decSparse(ctx, buf, v, n);
		case 'complex'
			[ctx,v] = decComplex(ctx, buf, v, n);
		otherwise
			[ctx,v] = decNumeric(ctx, buf, v, n, cid);
		end
		v = reshape(v, vsz);
		return;
	end

	% Check ubound. We must be able to assign v to out without overflow.
	ub = size(ctx.ubound, 2 - int32(isnumeric(v) || islogical(v)));
	if n > ub || numel(v) > ub
		ctx = fail(ctx, 'numelLimit');
		return;
	end

	% Standalone code uses v to guide the decoding process while verifying that
	% the buffer contains a valid encoding of v.
	if isnumeric(v) && isreal(v)
		[ctx,out] = decNumeric(ctx, buf, v, n, cid);
	elseif isnumeric(v) && ~isreal(v) && cid == cls2cid('complex')
		[ctx,out] = decComplex(ctx, buf, v, n);
	elseif islogical(v) && cid == cls2cid('logical')
		[ctx,out] = decLogical(ctx, buf, v, n);
	elseif ischar(v) && (cid == cls2cid('char8') || cid == cls2cid('char16'))
		[ctx,out] = decChar(ctx, buf, v, n, cid);
	elseif iscell(v) && cid == cls2cid('cell')
		[ctx,out] = decCell(ctx, buf, v, n);
	elseif isstruct(v) && cid == cls2cid('struct')
		[ctx,out] = decStruct(ctx, buf, v, n);
	else
		ctx = fail(ctx, 'classMismatch');
		return;
	end

	% v's shape determines what can be assigned to it
	if isempty(ctx.err)
		if isscalar(v)
			if ~isscalar(out)
				ctx = fail(ctx, 'sizeMismatch');
			elseif iscell(v)
				v{1} = out{1};
			else
				v(1) = out(1);
			end
		elseif size(v,1) ~= 1 && size(v,2) == 1
			v = out;
		elseif size(v,1) == 1 && size(v,2) ~= 1
			v = reshape(out, 1, numel(out));
		elseif size(v,1) ~= 1 && size(v,2) ~= 1
			v = reshape(out, vsz);
		end
	end
end

function [ctx,out] = decNumeric(ctx, buf, v, n, cid)
	if ~ctx.cgen
		[ctx,i,j] = consume(ctx, n*cid2bpe(cid));
		out = typecast(buf(i:j), cid2cls(cid));
		if ctx.swap
			out = swapbytes(out);
		end
		return;
	end
	coder.varsize('out', [ubound(ctx,1),1]);
	if cid == cls2cid(class(v))
		bpe = cid2bpe(cls2cid(class(v)));
		[ctx,i,j] = consume(ctx, n*bpe);
		if isa(v, 'uint8')
			out = buf(i:j);
		else
			coder.varsize('dat', [ubound(ctx,1)*bpe,1]);
			dat = buf(i:j);
			out = typecast(dat, class(v));
			if ctx.swap
				out = swapbytes(out);
			end
		end
	else
		ctx = fail(ctx, 'classMismatch');
		out = reshape(v, numel(v), 1);
	end
end

function [ctx,out] = decComplex(ctx, buf, v, n)
	if isempty(ctx.cgen)
		coder.varsize('out', 're', 'im', [ubound(ctx,1),1]);
	end
	[ctx,cid,~,~] = decTag(ctx, buf);
	[ctx,re] = decNumeric(ctx, buf, real(v(:)), n, cid);
	[ctx,im] = decNumeric(ctx, buf, imag(v(:)), n, cid);
	if numel(re) == numel(im)
		out = complex(re, im);
	else
		ctx = fail(ctx, 'corruptBuf');
		out = reshape(v, numel(v), 1);
	end
end

function [ctx,out] = decLogical(ctx, buf, v, n)
	if isempty(ctx.cgen)
		coder.varsize('out', 'dat', [ubound(ctx,1),1]);
	end
	[ctx,i,j] = consume(ctx, n);
	dat = buf(i:j);
	out = logical(dat);
end

function [ctx,out] = decSparse(ctx, buf, v, n)
	[ctx,idx] = decNext(ctx, buf, []);
	[ctx,nze] = decNext(ctx, buf, []);
	out = sparse(double(idx), 1, nze, double(n), 1);
end

function [ctx,out] = decChar(ctx, buf, v, n, cid)
	if isempty(ctx.cgen)
		coder.varsize('out', 'dat', [ubound(ctx,2),1]);
	end
	if cid == cls2cid('char8')
		[ctx,i,j] = consume(ctx, n);
		dat = buf(i:j);
		out = char(dat);
	elseif ~ctx.cgen
		dat = zeros(0, 1, 'uint16');
		[ctx,dat] = decNumeric(ctx, buf, dat, n, cls2cid('uint16'));
		out = char(dat);
	else
		ctx = fail(ctx, 'unicodeChar');
		out = reshape(v, numel(v), 1);
	end
end

function [ctx,out] = decCell(ctx, buf, v, n)
	if ~ctx.cgen
		v = {[]};
	else
		coder.varsize('out', [ubound(ctx,2),1]);
		if isempty(v)
			ctx = fail(ctx, 'emptyValue');
			out = reshape(v, numel(v), 1);
			return;
		end
	end
	out = cell(n, 1);
	for i = 1:numel(out)
		[ctx,out{i}] = decNext(ctx, buf, v{1});
	end
end

function [ctx,out] = decStruct(ctx, buf, v, n)
	if ~ctx.cgen
		[ctx,fields] = decNext(ctx, buf, []);
		fieldvals = cell(1, 2*numel(fields));
		fieldvals(1:2:numel(fieldvals)) = fields;
		for i = 2:2:numel(fieldvals)
			vals = cell(n, 1);
			for j = 1:n
				[ctx,vals{j}] = decNext(ctx, buf, []);
			end
			fieldvals{i} = vals;
		end
		out = struct(fieldvals{:});
		return;
	end

	% Ideally, bfn{:} should be limited to namelengthmax (63), but the decoder
	% can't enforce two separate limits for char arrays.
	coder.varsize('out', 'bfn', [ubound(ctx,2),1]);
	coder.varsize('bfn{:}', [1,ubound(ctx,2)]);
	if isempty(v)
		ctx = fail(ctx, 'emptyValue');
		out = reshape(v, numel(v), 1);
		return;
	end

	% Decode data for matching fields, ignore v fields that weren't encoded,
	% skip encoded fields that aren't in v. At least one field must match, but
	% the order may be different.
	out = repmat(v(1), n, 1);
	vfn = fieldnames(v);
	bfn = {'';''};
	err = ~isempty(vfn);
	[ctx,bfn] = decNext(ctx, buf, bfn);
	for i = 1:numel(bfn)
		match = false;

		% Must use this form to make vfn{j} a compile-time constant
		for j = 1:numel(vfn)
			if strcmp(bfn{i}, vfn{j})
				match = true;
				err = false;
				for k = 1:n
					[ctx,out(k).(vfn{j})] = decNext(ctx, buf, v(1).(vfn{j}));
				end
				break;
			end
		end
		if ~match
			for k = 1:n
				ctx = skip(ctx, buf, []);
			end
		end
	end
	if err
		ctx = fail(ctx, 'invalidStruct');
	end
end

function [ctx,n] = skip(ctx, buf, expect)
	[ctx,cid,vsz,n] = decTag(ctx, buf);
	if ~isempty(expect) && all(cid ~= expect)
		ctx = fail(ctx, 'corruptBuf');
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
			ctx = skip(ctx, buf, []);
		end
	case cls2cid('struct')
		[ctx,nf] = skip(ctx, buf, cls2cid('cell'));
		for i = 1:nf*n
			ctx = skip(ctx, buf, []);
		end
	case cls2cid('sparse')
		ctx = skip(ctx, buf, ...
				[cls2cid('uint8'),cls2cid('uint16'),cls2cid('uint32')]);
		ctx = skip(ctx, buf, [cls2cid('double'),cls2cid('logical')]);
	case cls2cid('complex')
		[ctx,cid,~,~] = decTag(ctx, buf);
		ctx = consume(ctx, 2*n*cid2bpe(cid));
	end
end

function [ctx,cid,vsz,n] = decTag(ctx, buf)
	[ctx,i,~] = consume(ctx, int32(1));
	cid = bitand(buf(i), 31);
	fmt = bitshift(buf(i), -5);
	if cid < 1 || 17 < cid
		ctx = fail(ctx, 'invalidTag');
	end

	% Decode size and calculate total number of elements
	vsz = ones(1, 2, 'int32');
	n = int32(1);
	switch fmt
	case 0
	case {1,2}
		[ctx,i,~] = consume(ctx, int32(1));
		vsz(fmt) = int32(buf(i));
		n = int32(buf(i));
	case 3
		[ctx,i,~] = consume(ctx, int32(2));
		vsz(:) = int32(buf(i:i+1));
		n = prod(vsz, 'native');
	case 4
		vsz = zeros(1, 2, 'int32');
		n = int32(0);
	otherwise
		[ctx,i,~] = consume(ctx, int32(1));
		szn = int32(buf(i));
		if szn ~= 2
			if szn < 2
				ctx = fail(ctx, 'invalidTag');
			elseif isempty(ctx.cgen)
				ctx = fail(ctx, 'ndimsLimit');
			else
				vsz = zeros(1, szn, 'int32');
			end
		end
		if isempty(ctx.err)
			% Separate function removes malloc calls from all other code paths
			[ctx,vsz,n] = decSize(ctx, buf, bitand(fmt, 3), vsz);
		end
	end
	if ~isempty(ctx.err)
		cid = uint8(0);
		vsz = zeros(1, 2, 'int32');
		n = int32(0);
	end
end

function [ctx,vsz,n] = decSize(ctx, buf, fmt, vsz)
	szn = int32(numel(vsz));
	if isempty(ctx.cgen)
		coder.inline('never');
		coder.varsize('u16', 'u32', [szn,1]);
	end
	switch fmt
	case 1
		[ctx,i,j] = consume(ctx, szn);
		u32 = uint32(buf(i:j));
	case 2
		u16 = zeros(0, 1, 'uint16');
		[ctx,u16] = decNumeric(ctx, buf, u16, szn, cls2cid('uint16'));
		u32 = uint32(u16);
	otherwise
		u32 = zeros(0, 1, 'uint32');
		[ctx,u32] = decNumeric(ctx, buf, u32, szn, cls2cid('uint32'));
	end
	p = prod(u32, 'native');
	n = int32(p);
	if numel(vsz) == numel(u32) && p <= intmax && max(u32) <= intmax
		vsz(:) = int32(u32);
	else
		ctx = fail(ctx, 'numelLimit');
	end
end

function [ctx,i,j] = consume(ctx, n)
	i = ctx.pos;
	ctx.pos = ctx.pos + n;
	j = ctx.pos - 1;
	if j >= ctx.len
		i = int32(1);
		j = int32(0);
		ctx = fail(ctx, 'corruptBuf');
	end
end

function ub = ubound(ctx,i)
	ub = double(size(ctx.ubound,i));
	if ub == intmax
		ub = Inf;
	end
end

function ctx = fail(ctx, err)
	if isempty(ctx.err)
		ctx.len = int32(0);
		ctx.err = err;
	end
	switch err
	case 'classMismatch'
		msg = 'Encoding does not match expected class.';
	case 'corruptBuf'
		msg = 'Buffer is corrupt.';
	case 'emptyValue'
		msg = 'Cell or struct does not contain any elements.';
	case 'invalidBuf'
		msg = 'Invalid buffer format.';
	case 'invalidPad'
		msg = 'Invalid buffer padding.';
	case 'invalidSig'
		msg = 'Invalid buffer signature.';
	case 'invalidStruct'
		msg = 'Invalid struct or field name mismatch.';
	case 'invalidTag'
		msg = 'Tag specifies an unknown class or invalid size.';
	case 'ndimsLimit'
		msg = 'Number of dimensions exceeds limit.';
	case 'numelLimit'
		msg = 'Number of elements exceeds limit.';
	case 'sizeMismatch'
		msg = 'Encoding does not match expected size.';
	case 'unicodeChar'
		msg = '16-bit characters are not supported.';
	end
	if ~isempty(ctx.cgen) || coder.target('MEX')
		error([mfilename ':' err], msg);
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
