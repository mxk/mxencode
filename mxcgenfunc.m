%MXCGENFUNC   Test function used by MXCGENTEST.

%   Written by Maxim Khitrov (February 2017)

function [buf,state] = mxcgenfunc(buf,i)
	state = initState();
	if ~isempty(buf)
		[state,~] = mxdecode(buf,[],state);
		% Normally, you'd want to handle any decoding errors here, but mex
		% functions throw errors instead of returning them to simplify testing.
	end

	state.scalar  = state.scalar + i;
	state.numeric = [state.numeric; numel(state.numeric)];
	state.complex = [state.complex, sum(state.complex)];
	state.logical = diag(repmat(true,1,size(state.logical,1)+1));
	state.char    = [state.char ('A'+mod(numel(state.char),26))];

	c = {'',''};
	coder.varsize('c', 'c{:}');
	[c,~] = mxdecode(state.cell, [], c);
	c{end+1} = state.char;
	[state.cell,~] = mxencode(c);

	for i = 1:numel(state.struct)
		f1 = state.struct(i).f1;
		state.struct(i).f1 = state.struct(i).f2;
		state.struct(i).f2 = f1;
	end

	[buf,~] = mxencode(state);
end

function v = initState()
	[c,~] = mxencode({});  % No cell arrays in structs (as of R2016b)
	v = struct( ...
		'scalar',  0, ...
		'numeric', reshape([], 0, 1), ...
		'complex', [1+2i,3+4i], ...
		'logical', logical([]), ...
		'char',    reshape('', 1, 0), ...
		'cell',    c, ...
		'struct',  struct('f1', {1,2}, 'f2', {3,4}) ...
	);
	coder.varsize('v.numeric', 'v.complex', 'v.logical', 'v.char', 'v.cell', ...
			'v.struct');
end
