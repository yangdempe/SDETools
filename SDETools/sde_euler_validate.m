function varargout=sde_euler_validate(dt,n,a,b,options)
%SDE_EULER_VALIDATE  Test SDE_EULER for performance and convergence order.
%   SDE_EULER_VALIDATE(DT,N)
%	YM = SDE_EULER_VALIDATE(DT,N)
%	YM = SDE_EULER_VALIDATE(DT,N,A,B)
%   YM = SDE_EULER_VALIDATE(DT,N,OPTIONS)
%	YM = SDE_EULER_VALIDATE(DT,N,A,B,OPTIONS)
%	[YM,YV] = SDE_EULER_VALIDATE(DT,N,...)
%
%   Example:
%       % Convergence order of Euler-Heun (Stratonovich) & Euler-Maruyama (Ito)
%       dt = logspace(-3,-1,3); n = 1e3; a = 1; b = 1;  % Try smaller b values
%       opts = sdeset('RandSeed',1);
%       sde_euler_validate(dt,n,a,b,opts);
%       opts = sdeset(opts,'SDEType','Ito');
%       sde_euler_validate(dt,n,a,b,opts);
%   
%   See also: SDE_EULER, SDE_GBM, SDE_MILSTEIN_VALIDATE, SDESET

%   For details of this validation method, see: Peter E. Kloeden and Eckhard
%   Platen, "Numerical solution of Stochastic Differential Equations,"
%   Springer-Verlag, 1992.

%   Andrew D. Horchler, adh9 @ case . edu, Created 11-1-10
%   Revision: 1.2, 5-3-13


% Check inputs and outputs
if nargin < 2
    error('SDETools:sde_euler_validate:NotEnoughInputs',...
          'Not enough input arguments.');
else
    if nargin < 5
        if nargin == 3
            error('SDETools:sde_euler_validate:InvalidInputPattern',...
                 ['Not enough input arguments: both A and B must be '...
                  'specified.']);
        end
        options = [];
    elseif nargin == 5
        if isempty(options) && (~sde_ismatrix(options) ...
                || any(size(options) ~= 0) || ~(isstruct(options) ...
                || iscell(options) || isnumeric(options))) ...
                || ~isempty(options) && ~isstruct(options)
            error('SDETools:sde_euler_validate:InvalidSDESETStruct',...
                  'Invalid SDE options structure.  See SDESET.');
        end
    else
        error('SDETools:sde_euler_validate:TooManyInputs',...
              'Too many input arguments.');
    end
end
if nargout > 2
    error('SDETools:sde_euler_validate:TooManyOutputs',...
          'Too many output arguments.');
end

% Check DT
if ~isvector(dt) || ~isfloat(dt) || ~isreal(dt) || ~all(isfinite(dt))
    error('SDETools:sde_euler_validate:InvalidDT',...
          'DT must be a finite real floating-point vector.');
end
ldt = length(dt);
if length(dt) < 2
    error('SDETools:sde_euler_validate:BadInputSizeDT',...
          'Input vector DT must have length >= 2.');
end
dt = sort(dt);

% Check N
if ~isscalar(n) || ~isfloat(n) || ~isreal(n) || ~isfinite(n)
    error('SDETools:sde_euler_validate:InvalidN',...
          'N must be a finite real floating-point scalar.');
end
if isempty(n) || n < 1 || n ~= floor(n)
    error('SDETools:sde_euler_validate:BadInputSizeN',...
          'Input N must be an integer >= 1.');
end

% Check A and B
if nargin >= 4
    if ~isscalar(a) || isempty(a) || ~isfloat(a) || ~isreal(a) || ~isfinite(a)
        error('SDETools:sde_euler_validate:InvalidA',...
              'A must be a finite real floating-point scalar.');
    end
    if ~isscalar(b) || isempty(b) || ~isfloat(b) || ~isreal(b) || ~isfinite(b)
        error('SDETools:sde_euler_validate:InvalidB',...
              'B must be a finite real floating-point scalar.');
    end
else
    a = 1;
    b = 1;
end

% Check random number generation
if ~isempty(sdeget(options,'RandFUN',[],'flag'))
    error('SHCTools:sde_euler_validate:InvalidRandFUN',...
          'This function only supports the default random number stream.');
end
if strcmp(sdeget(options,'Antithetic','no','flag'),'yes')
    error('SHCTools:sde_euler_validate:Antithetic',...
          'This function does not support antithetic random variates.');
end

% Set random seed unless already specified
if isempty(sdeget(options,'RandSeed',[],'flag'))
    options = sdeset(options,'RandSeed',1);
end

% Override non-diagonal noise, ConstFFUN, and ConstGFUN settings
options = sdeset(options,'DiagonalNoise','yes','ConstFFUN','no',...
    'ConstGFUN','no');

% Get SDE type for plot
SDEType = sdeget(options,'SDEType','Stratonovich','flag');

t0 = 0;
tf = 20*dt(end);
y0 = ones(n,1);

f = @(t,y)a*y;
g = @(t,y)b*y;
Ym(ldt,1) = 0;
Yv(ldt,1) = 0;

% Warm up for timing
[Yeuler,W] = sde_euler(f,g,[t0 t0+dt(1)],y0,options);	%#ok<NASGU,ASGLU>

% Loop through time-steps
ttotal = 0;
nsteps = 0;
for i=1:length(dt)
    t = t0:dt(i):tf;
    nsteps = nsteps+length(t);
    
    tic
    [Yeuler,W] = sde_euler(f,g,t,y0,options);
    ttotal = ttotal+toc;
    
    Ygbm = sde_gbm(a,b,[t0 tf],y0,sdeset(options,'RandFun',W([1 end],:)));
    
    % Calculate error between analytic and simulated solutions
    Yerr = abs(Ygbm(end,:)-Yeuler(end,:));
    Ym(i) = mean(Yerr);
    Yv(i) = std(Yerr);
end

% Variable output
if nargout == 0
    disp(['Total simulation time: ' num2str(ttotal) ' seconds']);
    disp(['Mean of ' int2str(n) ' simulations/time-step: ' ...
        num2str(ttotal/(nsteps)) ' seconds']);
else
    varargout{1} = Ym;
    if nargout == 2
        varargout{2} = Yv;
    end
end

% Plot results
figure
orders = [0.5 1.0 1.5 2.0]';
z = ones(length(orders),1);
xx = z*dt([1 end]);
logdt = log10(dt(end)/dt(1));
yy = Ym(1)*[z 10.^(orders*logdt)];
loglog(dt,Ym,'b.-',dt,Ym+Yv,'c',xx',yy','k')
text(xx(:,2)*10^(0.02*logdt),yy(:,2),cellstr(num2str(orders,'%1.1f')))
axis([dt(1) dt(end) Ym(1) yy(end,2)])
axis square
grid on
title(['SDE_EULER - ' SDEType ' - Convergence Order - ' int2str(n) ...
       ' simulations/time-step, A = ' num2str(a) ', B = ' num2str(b)],...
       'Interpreter','none')
xlabel('dt')
ylabel('Average Absolute Error')