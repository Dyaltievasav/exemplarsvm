function [models,mining_queue] = mine_negatives(models, mining_queue, bg, ...
                                                mining_params, iteration, ...
                                                bgval, validation_queue)
%% Mine negatives (for a set of models) and update the current
%% classifiers inside models 
%%
%% Tomasz Malisiewicz (tomasz@cmu.edu)
for q = 1:length(models)
  lastw{q} = models{q}.model.w;
  lastb{q} = models{q}.model.b;
end

%during first few iterations, we take many windows per image
if iteration <= mining_params.early_late_cutoff
  mining_params.detection_threshold = mining_params.early_detection_threshold;
else
  %in later iterations when we pass through many images, we use SVM cutoff
  mining_params.detection_threshold = mining_params.late_detection_threshold;
end

[hn, mining_queue, mining_stats] = ...
    load_hn_fg(models, mining_queue, bg, mining_params);

for i = 1:length(models)
  models{i} = add_new_detections(models{i},hn.xs{i},hn.objids{i});
end


% for i = 1:length(hn.objids)
%   allids{i} = cellfun(@(x)x.curid,hn.objids{i});
% end
% allids = [allids{:}];
% uids = unique(allids);
% r = randperm(length(uids));
% utrain = uids(r(1:round(length(r)/2)));
% uval = setdiff(uids,utrain);

% for i = 1:length(hn.objids)
%   curids = cellfun(@(x)x.curid,hn.objids{i});
%   trains = ismember(curids,utrain);
%   vals = ~trains;
%   hn.valxs{i} = hn.xs{i}(:,vals);
%   hn.xs{i} = hn.xs{i}(:,trains);
  
%   hn.valobjids{i} = hn.objids{i}(vals);
%   hn.objids{i} = hn.objids{i}(trains);
  
%   models{i}.model.nsv = cat(2,models{i}.model.nsv,hn.xs{i});
%   models{i}.model.vsv = cat(2,models{i}.model.vsv,hn.valxs{i});
  

%   models{i}.model.svids = cat(2,models{i}.model.svids, ...
%                               hn.objids{i});

%   models{i}.model.vsvids = cat(2,models{i}.model.vsvids, ...
%                               hn.valobjids{i});
% end

for q = 1:length(models)
  fprintf(1,'about to svm\n');
  if (size(models{q}.model.nsv,2) >= mining_params.MAX_WINDOWS_BEFORE_SVM) || ...
    (iteration == mining_params.MAXITER) || (length(mining_queue) == 0)
    fprintf(1,' --- REAL svm\n');
    
    [models{q}] = update_the_model(models, q, mining_params, lastw, ...
                                   iteration, mining_stats, bg);
  else
    fprintf(1,' --- NO svm\n');
  end
end


function [m] = update_the_model(models,index,mining_params, lastw, ...
                                iteration, mining_stats, bg)
%% UPDATE the current SVM and show the results

m = models{index};
m.iteration = m.iteration + 1;

%TODO: Remove redundant SVs here

%bad set is old support vectors and newly chosen objects
badx = [m.model.nsv];
badids = [m.model.svids];

goodx = [m.model.x];
superx = [goodx badx];
rstart = m.model.w(:)'*badx-m.model.b;
supery = cat(1,...
             +1*ones(size(goodx,2),1),...
             -1*ones(size(badx,2),1));



% m3 = [];

% %% if exemplar comes with a mask, then we restring learning to weights within
% %% allowable region, if no mask then create a full one which
% %% doesn't eliminate anything
% if isfield(m.model,'mask')
%   fdim = features;
%   m3 = logical(repmat(m.model.mask,[1 1 fdim]));
%   m3 = m3(:);
% end

old_scores = m.model.w(:)'*superx - m.model.b;
[m] = do_svm(m, mining_params);

wex = m.model.w(:);
b = m.model.b;

r = m.model.w(:)'*badx - m.model.b;

if strmatch(m.models_name,'dalal')
  %% here we take the best exemplars
  allscores = wex'*m.model.x - b;
  [aa,bb] = sort(allscores,'descend');
  [aabad,bbbad] = sort(r,'descend');
  maxbad = aabad(ceil(.05*length(aabad)));
  LEN = max(sum(aa>=maxbad), m.model.keepx);
  m.model.x = m.model.x(:,bb(1:LEN));
  fprintf(1,'dalal:WE NOW HAVE %d exemplars in category\n',LEN);
end

svs = find(r >= -1.0000);

%KEEP 3#SV vectors (but at most max_negatives of them)
total_length = ceil(mining_params.beyond_nsv_multiplier*length(svs));
total_length = min(total_length,mining_params.max_negatives);

[alpha,beta] = sort(r,'descend');
svs = beta(1:min(length(beta),total_length));
m.model.nsv = badx(:,svs);
m.model.svids = badids(svs);

%Keep as many validation vectors as training negative support vectors
r = wex'*m.model.vsv - m.model.b;
[alpha,beta] = sort(r,'descend');
vsvs = beta(1:min(length(beta),total_length));
m.model.vsv = m.model.vsv(:,vsvs);
m.model.vsvids = m.model.vsvids(vsvs);

% Append new w to trace
m.model.wtrace{end+1} = m.model.w;
m.model.btrace{end+1} = m.model.b;

%if DISPLAY == 0
%  return;
%end

%% update friends here
if 0
  VOCinit;
  fg = get_pascal_bg('trainval',m.cls);
  fg = setdiff(fg,sprintf(VOCopts.imgpath,m.curid));
  
  fgq = initialize_mining_queue(fg);
  fgq = fgq(1:20);
  mp = get_default_mining_params;
  mp.MAX_WINDOWS_PER_IMAGE = 10;
  mp.MAX_WINDOWS_BEFORE_SVM = 100000;
  [hn2] = load_hn_fg({m}, fgq, fg, mp);
  
  m.model.fsv = cat(2,m.model.fsv,hn2.xs{1});
  m.model.fsvids = cat(2,m.model.fsvids,hn2.objids{1});
  [alpha,beta] = sort(m.model.w(:)'*m.model.fsv,'descend');
  beta = beta(1:min(length(beta),1000));
  m.model.fsv = m.model.fsv(:,beta);
  m.model.fsvids = m.model.fsvids(beta);
end

%TODO: make sure overlapping windows get capped since now we can
%get duplicates added here...

figure(2)
clf
show_cool_os(m)

if (mining_params.dump_images == 1) || ...
      (mining_params.dump_last_image == 1 && ...
       m.iteration == mining_params.MAXITER)
  set(gcf,'PaperPosition',[0 0 20 5]);
  print(gcf,sprintf('%s/%s.%d_iter=%05d.png', ...
                    mining_params.final_directory,m.curid,...
                    m.objectid,m.iteration),'-dpng'); 
end

%% HERE WE DRAW THE FIGURES
figure(1)
clf
[negatives,vals,pos,m] = find_set_membership(m);
Isv1 = get_sv_stack(m,bg,12,12);
imagesc(Isv1)
axis image
axis off
title('Exemplar Weights + Sorted Matches')

if (mining_params.dump_images == 1) || ...
      (mining_params.dump_last_image == 1 && ...
       m.iteration == mining_params.MAXITER)

  imwrite(Isv1,sprintf('%s/%s.%d_iter_I=%05d.png', ...
                    mining_params.final_directory,m.curid,...
                    m.objectid,m.iteration),'png');
end
