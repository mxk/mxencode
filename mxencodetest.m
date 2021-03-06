%MXENCODETEST   Unit tests for MXENCODE/MXDECODE functions.
%
%   RESULT = RUNTESTS('mxencodetest') runs all unit tests.
%
%   MXENCODETEST(true) runs all unit tests and generates code coverage report.
%
%   See also MXENCODE, MXDECODE, RUNTESTS.

%   Written by Maxim Khitrov (February 2017)

function tests = mxencodetest(coverage)
	if nargout == 1
		tests = functiontests(localfunctions);
	elseif nargin == 1 && coverage
		import matlab.unittest.TestRunner;
		import matlab.unittest.plugins.CodeCoveragePlugin;
		root = fileparts(mfilename('fullpath'));
		runner = TestRunner.withTextOutput;
		runner.addPlugin(CodeCoveragePlugin.forFolder(root))
		runner.run(testsuite(mfilename));
	else
		runtests(mfilename);
	end
end

function setup(tc)
	tc.TestData.cgen = false;
	tc.TestData.sig = [];
	tc.TestData.byteOrder = '';
	tc.TestData.ubound = Inf;
end

function testEmpty(tc)
	s = [0,0];      veq(tc, reshape([],s), 1);
	s = [0,1];      veq(tc, reshape([],s), 1+1);
	s = [1,0];      veq(tc, reshape([],s), 1+1);
	s = [0,255];    veq(tc, reshape([],s), 1+numel(s));
	s = [0,256];    veq(tc, reshape([],s), 1+1+numel(s)*2);
	s = [65535,0];  veq(tc, reshape([],s), 1+1+numel(s)*2);
	s = [0,65536];  veq(tc, reshape([],s), 1+1+numel(s)*4);
	s = [intmax,0]; veq(tc, reshape([],s), 1+1+numel(s)*4);

	if tc.TestData.cgen
		encErr(tc, reshape([],0:2), 'ndimsLimit');
		decErr(tc, mxencode(reshape([],0:2)), 'ndimsLimit');
		return;
	end

	s = [0:2];             veq(tc, reshape([],s), 1+1+numel(s));
	s = [0,1,255];         veq(tc, reshape([],s), 1+1+numel(s));
	s = [0,ones(1,253),2]; veq(tc, reshape([],s), 1+1+numel(s));
	s = [1,zeros(1,254)];  veq(tc, reshape([],s), 1+1+numel(s));
	s = [0,1,256];         veq(tc, reshape([],s), 1+1+numel(s)*2);
	s = [intmax,1,0];      veq(tc, reshape([],s), 1+1+numel(s)*4);
end

function testSizeFormat(tc)
	i = uint8(255);
	s = [0,0];     veq(tc, randi(i,s,'uint8'), 1+prod(s));
	s = [0,1];     veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,0];     veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,1];     veq(tc, randi(i,s,'uint8'), 1+prod(s));
	s = [1,2];     veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [3,1];     veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,4];     veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [5,1];     veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,255];   veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [255,1];   veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [2,3];     veq(tc, randi(i,s,'uint8'), 1+2+prod(s));
	s = [255,255]; veq(tc, randi(i,s,'uint8'), 1+2+prod(s));
	s = [255,256]; veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [1,65535]; veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [65535,1]; veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [1,65536]; veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*4+prod(s));
	s = [65536,1]; veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*4+prod(s));

	if tc.TestData.cgen
		return;
	end

	s = [2,3,2,4];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)+prod(s));
	s = [2,3,255];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)+prod(s));
	s = [2,256,3];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [2,256,1,2];   veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [1,65536,1,2]; veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*4+prod(s));
end

function testNumeric(tc)
	classes = numericClasses();
	for i = 1:numel(classes)
		cls = classes{i};
		len = 1 + bytesPerElement(cls);
		veq(tc, cast([],cls), 1);
		veq(tc, cast(0,cls), len);
		if any(strcmp(cls, {'double','single'}))
			veq(tc, realmin(cls), len);
			veq(tc, realmax(cls), len);
			veq(tc, cast(NaN,cls), len);
			veq(tc, cast(+Inf,cls), len);
			veq(tc, cast(-Inf,cls), len);
		else
			veq(tc, intmin(cls), len);
			veq(tc, intmax(cls), len);
		end
	end
end

function testComplex(tc)
	classes = numericClasses();
	for i = 1:numel(classes)
		cls = classes{i};
		bpe = bytesPerElement(cls);
		v = 1+2i;            veq(tc, cast(v,cls), 1+1+bpe+bpe);
		v = [1+2i,3;4,5+6i]; veq(tc, cast(v,cls), 1+2+1+4*bpe+4*bpe);
		v(256,1) = 1+2i;     veq(tc, cast(v,cls), 1+1+2*2+1+512*bpe+512*bpe);
	end

	buf = mxencode(1+2i);
	buf(13:20) = [];
	decErr(tc, buf, 'corruptBuf', 1+2i);
end

function testLogical(tc)
	veq(tc, logical([]), 1);
	veq(tc, true, 1+1);
	veq(tc, false, 1+1);
	veq(tc, [false false; false true; true false; true true], 1+2+8);
end

function testSparse(tc)
	v = sparse([]);        veq(tc, v, 1 + 1 + 1);
	v = sparse([0]);       veq(tc, v, 1 + 1 + 1);
	v = sparse([false]);   veq(tc, v, 1 + 1 + 1);
	v = sparse([1]);       veq(tc, v, 1 + 1+1 + 1+8);
	v = sparse([true]);    veq(tc, v, 1 + 1+1 + 1+1);
	v = sparse([1+2i]);    veq(tc, v, 1 + 1+1 + 1+1+2*8);
	v = sparse([0 1]);     veq(tc, v, 1+1 + 1+1 + 1+8);
	v = sparse([1 0;2 3]); veq(tc, v, 1+2 + 1+1+3 + 1+1+3*8);
	v = sparse(255,255,1); veq(tc, v, 1+2 + 1+2 + 1+8);
	v = sparse(1,65536,2); veq(tc, v, 1+1+2*4 + 1+4 + 1+8);

	v = sparse([1+2i,3;4,5+6i]); veq(tc, v, 1+2 + 1+1+4 + 1+1+1+4*8+4*8);
	v(256,1) = 1+2i;             veq(tc, v, 1+1+2*2 + 1+1+5*2 + 1+1+1+5*8+5*8);
end

function testChar(tc)
	v = char([]);        veq(tc, v, 1);
	v = char([0]);       veq(tc, v, 1+numel(v));
	v = char([255]);     veq(tc, v, 1+numel(v));
	v = char([0,255]);   veq(tc, v, 1+1+numel(v));
	v = char([0,1;2,3]); veq(tc, v, 1+2+numel(v));
	v = char([1:255]);   veq(tc, v, 1+1+numel(v));
	v = char([0:255]');  veq(tc, v, 1+1+2*2+numel(v));

	if tc.TestData.cgen
		v = char(256); decErr(tc, mxencode(v), 'unicodeChar', v);
		return;
	end

	v = char([256]);     veq(tc, v, 1+numel(v)*2);
	v = char([65535]);   veq(tc, v, 1+numel(v)*2);
	v = char([0,65535]); veq(tc, v, 1+1+numel(v)*2);
	v = char([0:65535]); veq(tc, v, 1+1+4*2+numel(v)*2);
end

function testCell(tc)
	v = {1};         veq(tc, v, 1 + 1+8);
	v = {1,2};       veq(tc, v, 1+1 + 1+8 + 1+8);
	v = {1,2;3,4};   veq(tc, v, 1+2 + 1+8 + 1+8 + 1+8 + 1+8);
	v = {{1}};       veq(tc, v, 1 + 1 + 1+8);
	v = {{1,2}};     veq(tc, v, 1 + 1+1 + 1+8 + 1+8);
	v = {{1;2};{3}}; veq(tc, v, 1+1 + 1+1 + 1+8 + 1+8 + 1+1+8);

	if tc.TestData.cgen
		f = @(tc, v, err, len) decErr(tc, ...
				mxencode(v, tc.TestData.sig, tc.TestData.byteOrder), err, v);
	else
		f = @(tc, v, err, len) veq(tc, v, len);
	end

	v = {};               f(tc, v, 'emptyValue',    1);
	v = {{}};             f(tc, v, 'emptyValue',    1 + 1);
	v = {{{}}};           f(tc, v, 'emptyValue',    1 + 1 + 1);
	v = {{},{}};          f(tc, v, 'emptyValue',    1+1 + 1 + 1);
	v = {{{},1}};         f(tc, v, 'emptyValue',    1 + 1+1 + 1 + 1+8);
	v = {1,'a'};          f(tc, v, 'classMismatch', 1+1 + 1+8 + 1+1);
	v = {{1},'a'};        f(tc, v, 'classMismatch', 1+1 + 1+1+8 + 1+1);
	v = {{'a'},{1,2}};    f(tc, v, 'classMismatch', 1+1 + 1+1+1 + 1+1+1+8+1+8);
	v = {{'a'};{1,true}}; f(tc, v, 'classMismatch', 1+1 + 1+1+1 + 1+1+1+8+1+1);
	v = {{1};{2,3}};      f(tc, v, 'sizeMismatch',  1+1 + 1+1+8 + 1+1+1+8+1+8);
end

function testStruct(tc)
	v = struct();                    veq(tc, v, 1+1);
	v = repmat(struct(), 2, 1);      veq(tc, v, 1+1 + 1);
	v = struct('abc',1);             veq(tc, v, 1 + 1+1+1+3 + 1+8);
	v = repmat(struct('a',1), 1, 2); veq(tc, v, 1+1 + 1+1+1 + 1+8+1+8);
	v = struct('a',1,'bc',2);        veq(tc, v, 1 + 1+1+1+1+1+1+2 + 1+8+1+8);
	v = struct('a',{{1}},'b',2);     veq(tc, v, 1 + 1+1+1+1+1+1 + 1+1+8 + 1+8);

	v = struct('ab',{1,2},'b',{[],2});
	veq(tc, v, 1+1 + 1+1+1+1+2+1+1 + 1+8+1+8 + 1+1+8);

	if tc.TestData.cgen
		v = struct([]);
		decErr(tc, mxencode(v), 'emptyValue', v);
		return;
	end

	v = struct([]);
	veq(tc, v, 1 + 1);

	v = struct('abc',struct('xyz',{}));
	veq(tc, v, 1 + 1+1+1+3 + 1 + 1+1+1+3);

	v = struct('abc',struct('xyz',{{}}));
	veq(tc, v, 1 + 1+1+1+3 + 1 + 1+1+1+3 + 1);

	v = struct('a',{1,2},'b',{2,[]},'f2',{struct(),[1,2]});
	veq(tc, v, 1+1 + 1+1+1+1+1+1+1+1+2 + 1+8+1+8 + 1+8+1 + 1+1+1+1+2*8);

	v = struct('a',{[],1;2,[]},'bc',{3,[];[],{4,struct('x',[])}});
	veq(tc, v, 1+2 + 1+1+1+1+1+1+2 + 1+1+8+1+8+1 + 1+8+1+1 + 1+1+1+8+1+1+1+1+1);
end

function testSkip(tc)
	skip = struct( ...
		'double',  [1,2,3], ...
		'uint8',   uint8([4,5,6]), ...
		'char',    'ABC', ...
		'cell1',   {{'abc','d'}}, ...
		'cell2',   {{{1,2},{3,4}}}, ...
		'struct',  struct('f1', repmat(struct(),2,2), 'f2', {struct()}), ...
		'sparse',  sparse(1), ...
		'complex', [1+2i,3+4i] ...
	);
	wrap = struct( ...
		'abc', 123, ...
		'skip', skip, ...
		'xyz', 456 ...
	);
	veq(tc, skip);
	veq(tc, wrap);
	buf = mxencode(wrap);

	tc.TestData.cgen = true;
	decErr(tc, buf, 'classMismatch', wrap);

	function verify()
		[v,err] = mxdecode(buf, [], wrap);
		tc.verifyEqual(v, wrap);
		tc.verifyEmpty(err);
	end

	wrap.skip = rmfield(wrap.skip, 'sparse');  verify();
	wrap.skip = rmfield(wrap.skip, 'double');  verify();
	wrap.skip = rmfield(wrap.skip, 'complex'); verify();
	wrap.skip.double = [1,2,3];                verify();
	wrap.skip.newField = true;                 verify();
	wrap.skip = struct();                      verify();
	wrap = rmfield(wrap, 'skip');              verify();
	wrap = struct();                           verify();

	buf = mxencode(struct('a',struct('b',[])));
	decErr(tc, buf, 'invalidStruct', struct('x',struct('b',[])));

	buf(8) = 1;
	decErr(tc, buf, 'corruptBuf', struct());
end

function testSig(tc)
	tc.TestData.sig = 0;   veq(tc, [], 1);
	tc.TestData.sig = 239; veq(tc, [], 1);
	tc.TestData.sig = 240; encErr(tc, [], 'invalidSig');

	byteOrder = tc.TestData.byteOrder;
	tc.verifyNotEqual(mxencode([], 0, byteOrder), mxencode([], 1, byteOrder));

	tc.TestData.sig = 239;
	buf = mxencode([], 0, byteOrder);
	decErr(tc, buf, 'invalidSig', []);
	tc.verifyEqual(mxdecode(buf, 0), []);

	tc.TestData.sig = [];
end

function testUbound(tc)
	tc.TestData.cgen = true;
	s1 = struct( ...
		'numeric', ones(1, 100), ...
		'logical', true(1, 100), ...
		'char',    '0123456789', ...
		'cell',    {0,1,2,3,4,5,6,7,8,9} ...
	);
	s2 = struct( ...
		'numeric', ones(1, 0), ...
		'logical', true(1, 0), ...
		'char',    '', ...
		'cell',    {0,1} ...
	);
	buf1 = mxencode(s1);
	buf2 = mxencode(s2);

	tc.TestData.ubound = [];       veq(tc, s1);
	tc.TestData.ubound = 100;      veq(tc, s1);
	tc.TestData.ubound = [100,10]; veq(tc, s1);
	tc.TestData.ubound = [];       veq(tc, s2);
	tc.TestData.ubound = 100;      veq(tc, s2);
	tc.TestData.ubound = [100,10]; veq(tc, s2);
	tc.TestData.ubound = [100,9];  decErr(tc, buf1, 'numelLimit', s2);
	tc.TestData.ubound = [99,10];  decErr(tc, buf1, 'numelLimit', s2);
	tc.TestData.ubound = [100,9];  decErr(tc, buf2, 'numelLimit', s1);
	tc.TestData.ubound = [99;10];  decErr(tc, buf2, 'numelLimit', s1);
end

function testError(tc)
	byteOrder = tc.TestData.byteOrder;
	tc.TestData.byteOrder = 'X';
	encErr(tc, [], 'invalidByteOrder');
	tc.TestData.byteOrder = byteOrder;

	v = @(x) x;                            encErr(tc, v, 'unsupportedClass');
	v = reshape([], [1 zeros(1, 255)]);    encErr(tc, v, 'ndimsLimit');
	v = sparse(4294967296,1,1);            encErr(tc, v, 'numelLimit');
	v = sparse(65536,65536);               encErr(tc, v, 'numelLimit');
	v = reshape([], [0,intmax('uint32')]); encErr(tc, v, 'numelLimit');
	v = zeros(268435456,1);                encErr(tc, v, 'bufLimit');

	buf = uint8([]);              decErr(tc, buf, 'invalidBuf');
	buf = uint8([0;1;0]);         decErr(tc, buf, 'invalidBuf');
	buf = uint8([0;0;0;0]);       decErr(tc, buf, 'invalidPad');
	buf = uint8([0;0;0;254]);     decErr(tc, buf, 'invalidSig');
	buf = uint8([0;1;0;254]);     decErr(tc, buf, 'invalidSig');
	buf = uint8([240;240;0;254]); decErr(tc, buf, 'invalidSig');
	buf = uint8([240;241;0;254]); decErr(tc, buf, 'invalidSig');
	buf = uint8([240;42;0;254]);  decErr(tc, buf, 'invalidTag');

	v = 'abc';
	buf = mxencode(v, [], byteOrder);
	buf(4) = 4;
	decErr(tc, buf, 'corruptBuf', v);

	v = sparse(1,0);
	buf = mxencode(v, [], byteOrder);
	buf(3) = bitor(buf(3), 31);
	decErr(tc, buf, 'invalidTag', v);

	v = zeros(1,2,3,'uint8');
	buf = mxencode(v, [], byteOrder);
	buf(4) = 1;
	decErr(tc, buf, 'invalidTag', v);

	v = zeros(intmax,0);
	buf = mxencode(v, [], byteOrder);
	buf(5:8) = 255;
	decErr(tc, buf, 'numelLimit', v);
end

function testByteOrder(tc)
	native = mxencode(0);
	if typecast(uint8([0 1]),'uint16') == 1
		tc.assertEqual(native, mxencode(0,[],'B'));
		tc.assertNotEqual(native, mxencode(0,[],'L'));
		tc.TestData.byteOrder = 'L';
	else
		tc.assertEqual(native, mxencode(0,[],'L'));
		tc.assertNotEqual(native, mxencode(0,[],'B'));
		tc.TestData.byteOrder = 'B';
	end
	testEmpty(tc);
	testSizeFormat(tc);
	testNumeric(tc);
	testComplex(tc);
	testLogical(tc);
	testSparse(tc);
	testChar(tc);
	testCell(tc);
	testStruct(tc);
	testSkip(tc);
	testSig(tc);
	testUbound(tc);
	testError(tc);
end

function testCgen(tc)
	tc.TestData.cgen = true;
	testEmpty(tc);
	testSizeFormat(tc);
	testNumeric(tc);
	testComplex(tc);
	testLogical(tc);
	testChar(tc);
	testCell(tc);
	testStruct(tc);
	testSig(tc);
	testError(tc);
end

function veq(tc, v, len)
	if tc.TestData.cgen
		[buf,err] = mxencode(v, tc.TestData.sig, tc.TestData.byteOrder);
		tc.assertEmpty(err);
	else
		buf = mxencode(v, tc.TestData.sig, tc.TestData.byteOrder);
	end
	if nargin == 3
		tc.verifyNumElements(buf, 2+len+double(bitcmp(buf(end))));
	end
	if tc.TestData.cgen
		[out,err] = mxdecode(buf, tc.TestData.sig, v, tc.TestData.ubound);
		tc.verifyEqual(out, v);
		tc.verifyEmpty(err);
	else
		tc.verifyEqual(mxdecode(buf, tc.TestData.sig), v);
	end
end

function encErr(tc, v, errid)
	f = @() mxencode(v, tc.TestData.sig, tc.TestData.byteOrder);
	if tc.TestData.cgen
		[buf,err] = f();
		tc.verifyEmpty(buf);
		tc.verifyEqual(err, errid);
	else
		tc.verifyError(f, ['mxencode:' errid]);
	end
end

function decErr(tc, buf, errid, v)
	if tc.TestData.cgen
		if nargin < 4
			v = [];
		end
		[v,err] = mxdecode(buf, tc.TestData.sig, v, tc.TestData.ubound);
		tc.verifyEqual(err, errid);
	else
		tc.verifyError(@() mxdecode(buf, tc.TestData.sig), ['mxdecode:' errid]);
	end
end

function classes = numericClasses()
	classes = {'double','single','int8','uint8','int16','uint16','int32', ...
			'uint32','int64','uint64'};
end

function bpe = bytesPerElement(cls)
	bpe = numel(typecast(cast(0,cls), 'uint8'));
end
