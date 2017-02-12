%MXCGENTEST   Unit tests for MXENCODE/MXDECODE functions in standalone mode.
%
%   RESULT = RUNTESTS('mxcgentest') runs all unit tests.
%
%   See also MXENCODE, MXDECODE, RUNTESTS.

%   Written by Maxim Khitrov (February 2017)

function tests = mxcgentest(coverage)
	tests = functiontests(localfunctions);
end

function testCgen(tc)
	make('mex');
	make('lib');
	mbuf = zeros(0, 1, 'uint8');
	cbuf = zeros(0, 1, 'uint8');
	for i = 0:10
		[mbuf,mstate] = mxcgenfunc(mbuf, i);
		[cbuf,cstate] = mxcgenfunc_mex(cbuf, i);
		tc.assertNotEmpty(mbuf);
		tc.assertEqual(mbuf, cbuf);
		tc.assertEqual(mstate, cstate);
	end
end

function make(cfgType)
	cfg = coder.config(cfgType);
	if strcmp(cfgType, 'lib')
		cfg.BuildConfiguration = 'Faster Runs';
		cfg.CodeReplacementLibrary = 'GNU C99 extensions';
		cfg.GenCodeOnly = true;
		cfg.GenerateExampleMain = 'DoNotGenerate';
		cfg.HardwareImplementation.ProdHWDeviceType = 'ARM Compatible->ARM 7';
		cfg.HardwareImplementation.ProdLongLongMode = true;
		cfg.MultiInstanceCode = true;
		cfg.TargetLangStandard = 'C99 (ISO)';
	end
	cfg.FilePartitionMethod = 'SingleFile';
	cfg.MATLABSourceComments = true;

	func = 'mxcgenfunc';
	buf  = coder.typeof(uint8([]), [Inf,1]);
	i    = coder.typeof(0);

	codegen('-config', cfg, '-d', ['codegen-' func '-' cfgType], ...
		func, '-args', {buf, i});
end
