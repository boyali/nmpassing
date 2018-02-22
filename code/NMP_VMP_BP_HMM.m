function HMM = NMP_VMP_BP_HMM
% This demo defines a hidden Markov model, generates data from it, then
% inverts this model using variational message passing and belief
% propagation. For biological plausibility, gradient schemes are used.
% HMM specification:
% A{g}(g,s{1},s{2},s{3},s{4},s{5}) - likelihood for outcome modality g
% B{f}(s{f},s{f})                  - transitions for state factor f
% D{f}(s{f})                       - prior for intial state (factor f)
% T                                - time steps

rng default

% Define generative model
%==========================================================================
% Likelihood matrix
%--------------------------------------------------------------------------
A{1}(:,:,1) = eye(3);
A{1}(:,:,2) = eye(3);
A{1}(:,:,3) = eye(3);

A{2}(:,:,1) = [1 0 0;
               0 1 1];
A{2}(:,:,2) = [1 0 0;
               0 1 1];
A{2}(:,:,3) = [1 0 0;
               0 1 1];
           
% Transition probabilities
%--------------------------------------------------------------------------
B{1} = [0.3 1  0.5;
        0   0  0.5;
        0.7 0  0 ];
    
B{2} = [0.3 1  0.5;
        0   0  0.5;
        0.7 0  0 ];


% Prior probabilities
%--------------------------------------------------------------------------
D{1} = [0 0 1]';
D{2} = [1 0 0]';

% Set up hmm structure
%--------------------------------------------------------------------------
hmm.A = A; % Likelihood
hmm.B = B; % Transitions
hmm.D = D; % Priors
hmm.T = 15; % Time

% Invert
%--------------------------------------------------------------------------
HMM = NMP_HMM_GP(hmm); % Generate data using HMM generative process
VMP = NMP_VMP_HMM(HMM);% Invert using variational message passing
BP  = NMP_BP_HMM(HMM); % Invert using belief propagation

HMM.VMP = VMP;
HMM.BP  = BP;

% Figures
%--------------------------------------------------------------------------
figure('Name','Posterior beliefs','Color','w')
nmp_plot_posteriors(HMM)

figure('Name','Belief updating','Color','w','Position',[400 50 600 590])
nmp_plot_updates(HMM)

figure('Name','Belief dynamics','Color','w','Position',[60 50 1200 590])
nmp_plot_dynamics(HMM)


function HMM = NMP_HMM_GP(hmm)
% This function takes a hidden Markov model and uses it to generate data
% The HMM should have the following fields:
% A - likelihood matrix
% B - transition matrix
% D - prior over initial states
% T - length of data vector

A = hmm.A;
B = hmm.B;
D = hmm.D;
T = hmm.T;

for f = 1:numel(D)
    s{f}(1) = find(cumsum(D{f})>=rand, 1);
    for t = 2:T
        s{f}(t) = find(cumsum(B{f}(:,s{f}(t-1)))>=rand,1);
    end
end

for f = numel(D)+1:5
    s{f}(1:T) = 1;
end

for t = 1:T
    for g = 1:numel(A)
        o{g}(t) = find(cumsum(A{g}(:,s{1}(t),s{2}(t),s{3}(t),s{4}(t),s{5}(t)))>=rand,1);
    end
end

HMM = hmm;
HMM.s = s;
HMM.o = o;

function VMP = NMP_VMP_HMM(hmm)
% This function takes an HMM, and uses variational message passing to
% compute approximate posterior beliefs about the states, given
% sequentially presented outcomes. The HMM should have the following
% fields:
% A - likelihood matrix
% B - transition matrix
% D - prior over initial states
% o - data (optional)
% T - length of data vector

A = hmm.A;
B = hmm.B;
D = hmm.D;
o = hmm.o;
T = hmm.T;

% Initialisation
%--------------------------------------------------------------------------
for f = 1:numel(D)
    Ns(f) = length(D{f});
    Qs{f} = ones(Ns(f),T)/Ns(f);
end

tau = 4;
Ni  = 16;
% Message passing
%--------------------------------------------------------------------------

for t = 1:T
    for i = 1:Ni
        for f = 1:numel(D)
            lnAo = zeros(size(Qs{f}));
            for tt = 1:T
                v = nmp_ln(Qs{f}(:,tt));
                if tt<t+1
                    for g = 1:numel(A)
                        lnA = permute(nmp_ln(A{g}(o{g}(tt),:,:,:,:,:)),[2 3 4 5 6 1]);
                        for fj = 1:numel(D)
                            if fj == f
                            else
                                lnAs = nmp_dot(lnA,Qs{fj}(:,tt),fj);
                                clear lnA
                                lnA = lnAs; clear lnAs
                            end
                        end
                        lnAo(:,tt) = lnAo(:,tt) + squeeze(lnA);
                    end
                end
                if tt == 1
                    lnD = nmp_ln(D{f});
                    lnBs = nmp_ln(B{f})'*Qs{f}(:,tt+1);
                elseif tt == T
                    lnBs = zeros(size(D{f}));
                    lnD  = nmp_ln(B{f})*Qs{f}(:,tt-1);
                else
                    lnD  = nmp_ln(B{f})*Qs{f}(:,tt-1);
                    lnBs = nmp_ln(B{f})'*Qs{f}(:,tt+1);
                end
                v = v + (lnD + lnBs + lnAo(:,tt) - v)/tau;
                Qs{f}(:,tt) = exp(v)/sum(exp(v));
                Xq{f}(:,tt,t,i) = Qs{f}(:,tt);
                clear v
            end
        end
    end
end

VMP    = hmm;
VMP.Qs = Qs; % Posteriors at end
VMP.Xq = Xq; % Posteriors throughout

function BP = NMP_BP_HMM(hmm)
% This function takes an HMM, and uses belief propagation to compute
% marginal beliefs about states, given serially presented outcomes. Unlike
% classical approaches to BP (e.g. Baum-Welch), we use a gradient ascent
% scheme that relies upon messages derived from posterior marginals
% The HMM should have the following fields:
% A - likelihood matrix
% B - transition matrix
% D - prior over initial states
% o - data (optional)
% T - length of data vector

A = hmm.A;
B = hmm.B;
D = hmm.D;
o = hmm.o;
T = hmm.T;

% Initialisation
%--------------------------------------------------------------------------
for f = 1:numel(D)
    Ns(f) = length(D{f});
    Qs{f} = ones(Ns(f),T)/Ns(f);
    Mf{f} = ones(Ns(f),T)/Ns(f); Mf{f}(:,1) = D{f};
    Mb{f} = ones(Ns(f),T)/Ns(f);
end

tau = 4;
Ni  = 16;
% Message passing
%--------------------------------------------------------------------------
for t = 1:T
    for i = 1:Ni
        for f = 1:numel(D)
            lnAo = zeros(size(Qs{f}));
            for tt = 1:T
                v = nmp_ln(Qs{f}(:,tt));
                if tt<t+1
                    for g = 1:numel(A)
                        Ao = permute(A{g}(o{g}(tt),:,:,:,:,:),[2 3 4 5 6 1]);
                        for fj = 1:numel(D)
                            if fj == f
                            else
                                As = nmp_dot(Ao,Qs{fj}(:,tt),fj);
                                clear Ao
                                Ao = As; clear As
                            end
                        end
                        lnAo(:,tt) = squeeze(nmp_ln(Ao)) + lnAo(:,tt);
                    end
                end
                
                % Update messages
                for ttt = 1:T
                    if ttt<t+1 && ttt<T
                        if ttt>1
                            vv = exp(nmp_ln(Qs{f}(:,ttt))-nmp_ln(Mb{f}(:,ttt))-lnAo(:,ttt));
                            Mf{f}(:,ttt) = vv/sum(vv);
                        end
                        vv = exp(nmp_ln(Qs{f}(:,ttt))-nmp_ln(Mf{f}(:,ttt))-lnAo(:,ttt));
                        Mb{f}(:,ttt) = vv/sum(vv);
                    end
                end
                % Update marginals
                if tt == 1
                    lnD = nmp_ln(D{f});
                else
                lnD  = nmp_ln(B{f}*Mf{f}(:,tt-1));
                end
                if tt<T
                lnBs = nmp_ln(B{f}'*Mb{f}(:,tt+1));
                else
                    lnBs = ones(size(Qs(:,1)));
                end
                v = v + (lnD + lnBs + lnAo(:,tt) - v)/tau;
                Qs{f}(:,tt) = exp(v)/sum(exp(v));
                Xq{f}(:,tt,t,i) = Qs{f}(:,tt);
            end
        end
    end
end

BP    = hmm;
BP.Qs = Qs;
BP.M.f = Mf;
BP.M.b = Mb;
BP.Xq  = Xq;

function y = nmp_ln(x)
% For numerical reasons
y = log(x+exp(-16));

function B = nmp_dot(A,s,f)
% multidimensional dot product along dimension f
d = zeros(1,5);
d(f) = 1;
for i = 2:5
    d(find(d==0,1))=i;
end
x = permute(s,d) + zeros(size(A));
B = sum(A.*x,f);
k = zeros(1,5);
k(f) = 5;
for i = 1:4
    k(find(k==0,1))=i;
end
B = permute(B,k);

function nmp_plot_posteriors(HMM)
Nf  = numel(HMM.B);
VMP = HMM.VMP;
BP  = HMM.BP;
for i = 1:Nf
    subplot(3,Nf,i)
    imagesc(1-VMP.Qs{i})
    title(['Posterior belief (VMP) factor ' num2str(i)])
    subplot(3,Nf,Nf+i)
    imagesc(1-BP.Qs{i})
    title(['Posterior belief (BP) factor ' num2str(i)])
    subplot(3,Nf,2*Nf+i)
    plot(HMM.s{i},'.r','MarkerSize',20)
    axis ij
    title(['True state - factor ' num2str(i)])
end
colormap gray

function nmp_plot_updates(HMM)
% M = [];

Xv = HMM.VMP.Xq;
Xb = HMM.BP.Xq;

Nf = numel(Xv);

for t = 1:HMM.T
    subplot(3,1,3)
    for g = 1:numel(HMM.o)
        plot(HMM.o{g}(1:t)+g/numel(HMM.o),'.','MarkerSize', 30), hold on
        axis([0 HMM.T+1 0 5])
        axis ij
        ylabel('Sensory data')
    end
    hold off
    for i = 1:size(Xv{1},4)
        for f = 1:Nf
            subplot(3,Nf,f)
            imagesc(1-Xv{f}(:,:,t,i))
            title(['Posterior belief (VMP) factor ' num2str(f)])
            subplot(3,Nf,Nf+f)
            imagesc(1-Xb{f}(:,:,t,i))
            title(['Posterior belief (BP) factor ' num2str(f)])
        end
        colormap gray
        
%         if numel(M)
%             M(end + 1) = getframe(gcf);
%         else
%             M = getframe(gcf);
%         end
%         im = frame2im(M(end));
%         [A,map] = rgb2ind(im,256);
%         if t==1 && i == 1
%             imwrite(A,map,'C:\Users\Thomas\Dropbox\Code\Neuronal message passing\NMP.gif','gif','LoopCount',Inf,'DelayTime',0.1);
%         else
%             imwrite(A,map,'C:\Users\Thomas\Dropbox\Code\Neuronal message passing\NMP.gif','gif','WriteMode','append','DelayTime',0.1);
%         end
        pause(0.01)
    end
end

function nmp_plot_dynamics(HMM)
% M = [];

Xv = HMM.VMP.Xq;
Xb = HMM.BP.Xq;

V = [];
B = [];
for f = 1:numel(Xv)
Vf{f} = [];
Bf{f} = [];
        for j = 1:size(Xv{f},3)
            for k = 1:size(Xv{f},4)
                v = Xv{f}(:,:,j,k);
                Vf{f}(end+1,:) = v(:);
                b = Xb{f}(:,:,j,k);
                Bf{f}(end+1,:) = b(:);
                clear v b
            end
        end
V(:,end+1:end+size(Vf{f},2)) = Vf{f};
B(:,end+1:end+size(Bf{f},2)) = Bf{f};
end
PV = pca(V);
PV1 = V*PV(:,1);
PV2 = V*PV(:,2);
PV3 = V*PV(:,3);

PB = pca(B);
PB1 = V*PB(:,1);
PB2 = V*PB(:,2);
PB3 = V*PB(:,3);

for i = 1:length(V)
    subplot(2,2,1)
    plot(1:i,V(1:i,:))
    title('Beliefs (VMP)')
    axis([0 length(V) 0 1])
    
    subplot(2,2,2)
    plot(1:i,B(1:i,:))
    title('Beliefs (BP)')
    axis([0 length(B) 0 1])
    
    subplot(2,4,5)
    plot(PV1(1:i),PV2(1:i))
    xlabel('PC 1')
    ylabel('PC 2')
    axis([min(PV1) max(PV1) min(PV2) max(PV2)]);
    axis square
    
    subplot(2,4,7)
    plot(PB1(1:i),PB2(1:i))
    xlabel('PC 1')
    ylabel('PC 2')
    axis([min(PB1) max(PB1) min(PB2) max(PB2)]);
    axis square
    
    subplot(2,4,6)
    plot(PV2(1:i),PV3(1:i))
    xlabel('PC 2')
    ylabel('PC 3')
    axis([min(PV2) max(PV2) min(PV3) max(PV3)]);
    axis square
    
    subplot(2,4,8)
    plot(PB2(1:i),PB3(1:i))
    xlabel('PC 2')
    ylabel('PC 3')
    axis([min(PB2) max(PB2) min(PB3) max(PB3)]);
    axis square
    drawnow
    
%     if numel(M)
%         M(end + 1) = getframe(gcf);
%     else
%         M = getframe(gcf);
%     end
%     im = frame2im(M(end));
%     [A,map] = rgb2ind(im,256);
%     if i==1
%         imwrite(A,map,'C:\Users\Thomas\Dropbox\Code\Neuronal message passing\Dynamics.gif','gif','LoopCount',Inf,'DelayTime',0.1);
%     else
%         imwrite(A,map,'C:\Users\Thomas\Dropbox\Code\Neuronal message passing\Dynamics.gif','gif','WriteMode','append','DelayTime',0.1);
%     end
end