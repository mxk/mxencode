%MXENCODETEST   Unit tests for MXENCODE/MXDECODE functions.
%   RESULT = RUNTESTS('mxencodetest') runs all unit tests.
%
%   MXENCODETEST(true) runs all unit tests and generates code coverage report.
%
%   See also MXENCODE, MXDECODE, RUNTESTS.

%   Written by Maxim Khitrov (January 2017)

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

function testEmpty(tc)
	s = [0,0];                veq(tc, reshape([],s), 1);
	s = [0,1];                veq(tc, reshape([],s), 1+1);
	s = [1,0];                veq(tc, reshape([],s), 1+1);
	s = [0:2];                veq(tc, reshape([],s), 1+1+numel(s));
	s = [0:254];              veq(tc, reshape([],s), 1+1+numel(s));
	s = [0,256];              veq(tc, reshape([],s), 1+1+numel(s)*2);
	s = [256,0];              veq(tc, reshape([],s), 1+1+numel(s)*2);
	s = [0,intmax('uint32')]; veq(tc, reshape([],s), 1+1+numel(s)*4);
	s = [intmax('uint32'),0]; veq(tc, reshape([],s), 1+1+numel(s)*4);
end

function testSizeFormat(tc)
	i = uint8(255);
	s = [0,0];         veq(tc, randi(i,s,'uint8'), 1+prod(s));
	s = [0,1];         veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,0];         veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,1];         veq(tc, randi(i,s,'uint8'), 1+prod(s));
	s = [1,2];         veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,3];         veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,4];         veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,5];         veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [1,255];       veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [255,1];       veq(tc, randi(i,s,'uint8'), 1+1+prod(s));
	s = [2,3];         veq(tc, randi(i,s,'uint8'), 1+2+prod(s));
	s = [255,255];     veq(tc, randi(i,s,'uint8'), 1+2+prod(s));
	s = [2,3,4];       veq(tc, randi(i,s,'uint8'), 1+1+numel(s)+prod(s));
	s = [2,3,2,4];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)+prod(s));
	s = [1,65535];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [65535,1];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [256,256];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [2,256,4];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [2,256,1,2];   veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*2+prod(s));
	s = [1,65536];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*4+prod(s));
	s = [65536,1];     veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*4+prod(s));
	s = [1,65536,1,2]; veq(tc, randi(i,s,'uint8'), 1+1+numel(s)*4+prod(s));
end

function testNumeric(tc)
	classes = numericClasses;
	for i = 1:numel(classes)
		cls = classes{i};
		len = 1 + bytesPerElement(cls);
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
	classes = numericClasses;
	for i = 1:numel(classes)
		cls = classes{i};
		bpe = bytesPerElement(cls);
		v = 1+2i;            veq(tc, cast(v,cls), 1+1+bpe+bpe);
		v = [1+2i,3;4,5+6i]; veq(tc, cast(v,cls), 1+2+1+4*bpe+4*bpe);
		v(256,1) = 1+2i;     veq(tc, cast(v,cls), 1+1+2*2+1+512*bpe+512*bpe);
	end
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
	v = sparse([1 0;1 1]); veq(tc, v, 1+2 + 1+1+3 + 1+1+3*8);
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
	v = char([65535]);   veq(tc, v, 1+numel(v)*2);
	v = char([0,65535]); veq(tc, v, 1+1+numel(v)*2);
	v = char([1:255]);   veq(tc, v, 1+1+numel(v));
	v = char([0:255]');  veq(tc, v, 1+1+2*2+numel(v));
	v = char([0:65535]); veq(tc, v, 1+1+4*2+numel(v)*2);
end

function testCell(tc)
	v = {};               veq(tc, v, 1);
	v = {{}};             veq(tc, v, 1 + 1);
	v = {{{}}};           veq(tc, v, 1 + 1 + 1);
	v = {1};              veq(tc, v, 1 + 1+8);
	v = {1,'a'};          veq(tc, v, 1+1 + 1+8 + 1+1);
	v = {{1}};            veq(tc, v, 1 + 1 + 1+8);
	v = {{{}, 1}};        veq(tc, v, 1 + 1+1 + 1 + 1+8);
	v = {{1},'a'};        veq(tc, v, 1+1 + 1+1+8 + 1+1);
	v = {{'a'},{1,true}}; veq(tc, v, 1+1 + 1+1+1 + 1+1+1+8+1+1);
end

function testStruct(tc)
	v = struct();
	veq(tc, v, 1+2);

	v = struct('a',1);
	veq(tc, v, 1+2 + 1+1+1+8);

	v = struct('a',1,'b',2);
	veq(tc, v, 1+2 + 1+1+1+8 + 1+1+1+8);

	v = struct('abc',struct('xyz',{}));
	veq(tc, v, 1+2 + 1+1+3 + 1+2 + 1+1+3);

	v = struct('abc',struct('xyz',{{}}));
	veq(tc, v, 1+2 + 1+1+3 + 1+2 + 1+1+3 + 1);

	v = struct('a',{{1}},'b',2);
	veq(tc, v, 1+2 + 1+1+1+1+8 + 1+1+1+8);

	v = struct('a',{1,2},'b',{2,[]});
	veq(tc, v, 1+1+2 + 1+1+1+8+1+8 + 1+1+1+8+1);

	v = struct('a',{1,2},'b',{2,[]},'f2',{struct(),[1,2]});
	veq(tc, v, 1+1+2 + 1+1+1+8+1+8 + 1+1+1+8+1 + 1+1+2+1+2+1+1+2*8);
end

function testError(tc)
	encErr(tc, @(x) x, 'unsupported');
	encErr(tc, sparse(4294967296,1,1), 'numelRange');

	kv = sprintfc('f%d', 1:2*65536);
	encErr(tc, struct(kv{:}), 'fieldCount');

	encErr(tc, reshape([], 0:255), 'ndimsRange');
	encErr(tc, sparse(65536,65536), 'numelRange');
	%encErr(tc, zeros(536870912,1), 'overflow');

	decErr(tc, uint8([]));

	buf = mxencode('abc');
	buf(4) = 255;
	decErr(tc, buf);

	buf = mxencode(sparse(1,0));
	buf(3) = bitor(buf(3), 31);
	decErr(tc, buf);
end

function veq(tc, v, len)
	buf = mxencode(v);
	if nargin == 3
		tc.verifyNumElements(buf, 2+len+double(bitcmp(buf(end))));
	end
	tc.verifyEqual(mxdecode(buf), v);
end

function encErr(tc, v, errid)
	if true
		tc.verifyError(@() mxencode(v), ['mxencode:' errid]);
	else
		tc.verifyEmpty(mxencode(v));
	end
end

function decErr(tc, buf)
	if true
		tc.verifyError(@() mxdecode(buf), 'mxdecode:invalidBuf');
	else
		tc.verifyEmpty(mxdecode(v));
	end
end

function classes = numericClasses
	classes = {'double','single','int8','uint8','int16','uint16','int32', ...
			'uint32','int64','uint64'};
end

function bpe = bytesPerElement(cls)
	bpe = numel(typecast(cast(0,cls), 'uint8'));
end
