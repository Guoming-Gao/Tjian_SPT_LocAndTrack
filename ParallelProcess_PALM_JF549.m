%   ParallelProcess_PALM_JF549.m
%   Anders Sejr Hansen, August 2016
clear; clc; close all; clearvars -global

%   DESCRIPTION
%   This script takes as input a folder with nd2 files and then outputs
%   workspaces with tracked single molecules. Briefly, it uses the
%   BioFormats package to read in nd2 files. Please double-check that this
%   does not change the pixel intensity values. Nikon keeps updating the
%   nd2 file format, so if you are using mis-matched Nikon Elements
%   software versions and bioformat versions, this is a major issue that
%   you should be aware of. Next, the script feeds the images as a 3D
%   matrix into the localization part of the MTT algorithm (Part 1) and
%   subsequently, the tracked particles are fed into the tracking part of
%   the MTT algorithm (Part 2). 

%   PARALLEL PROCESSING UPDATE
%   For running things in parallel, we cannot save inside a PARFOR loop. In
%   older versions of MATLAB, the workaround was to write a function and
%   then save workspace output within the function, but this does not work
%   in the never versions of MATLAB. So instead save the output as a dummy
%   structured array and then run a final loop to save the workspaces. 

%%%%%%%%%%%%%%%%%%%% DEFINE INPUT AND OUTPUT PATHS %%%%%%%%%%%%%%%%%%%%%%%%
% specify input path with nd2 files:
%input_path=('/Users/anderssejrhansen/Dropbox/MatLab/Lab/Microscopy/SingleParticleTracking/SoftwarePackages/SLIMFAST_batch_fordist/TestData/');
input_path=('/Users/anderssejrhansen/Dropbox/DataStorage/MicroscopyData/fixedPALM/20160811_U2OS_Halo-NLS_ParamSearch/');
output_path=('/Users/anderssejrhansen/Dropbox/DataStorage/MicroscopyData/fixedPALM/VerifyTestHaloNLS/');
NumWorkers = 4; % input the maximum number of workers available on your computer
LocalizationError = -6; % Localization Error: -6 = 10^-6
EmissionWavelength = 580; % wavelength in nm; consider emission max and filter cutoff
ExposureTime = 25; % in milliseconds
NumDeflationLoops = 0; % Generaly keep this to 0; if you need deflation loops, you are imaging at too high a density;
MaxExpectedD = 0.05; % The maximal expected diffusion constant for tracking in units of um^2/s;
NumGapsAllowed = 1; % the number of gaps allowed in trajectories
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% DEFINE STRUCTURED ARRAY WITH ALL THE SPECIFIC SETTINGS FOR LOC AND TRACK
% imaging parameters
impars.PixelSize=0.16; % um per pixel
impars.psf_scale=1.35; % PSF scaling
impars.wvlnth= EmissionWavelength/1000; %emission wavelength in um
impars.NA=1.49; % NA of detection objective
impars.psfStd= impars.psf_scale*0.55*(impars.wvlnth)/impars.NA/1.17/impars.PixelSize/2; % PSF standard deviation in pixels
impars.FrameRate= ExposureTime/1000; %secs
impars.FrameSize= ExposureTime/1000; %secs

% localization parameters
locpars.wn=9; %detection box in pixels
locpars.errorRate= LocalizationError; % error rate (10^-)
locpars.dfltnLoops= NumDeflationLoops; % number of deflation loops
locpars.minInt=0; %minimum intensity in counts
locpars.maxOptimIter= 50; % max number of iterations
locpars.termTol= -2; % termination tolerance
locpars.isRadiusTol=false; % use radius tolerance
locpars.radiusTol=50; % radius tolerance in percent
locpars.posTol= 1.5;%max position refinement
locpars.optim = [locpars.maxOptimIter,locpars.termTol,locpars.isRadiusTol,locpars.radiusTol,locpars.posTol];
locpars.isThreshLocPrec = false;
locpars.minLoc = 0;
locpars.maxLoc = inf;
locpars.isThreshSNR = false;
locpars.minSNR = 0;
locpars.maxSNR = inf;
locpars.isThreshDensity = false;

% tracking parameters
trackpars.trackStart=1;
trackpars.trackEnd=inf;
trackpars.Dmax= MaxExpectedD;
trackpars.searchExpFac=1.2;
trackpars.statWin=10;
trackpars.maxComp=3;
trackpars.maxOffTime=NumGapsAllowed;
trackpars.intLawWeight=0.9;
trackpars.diffLawWeight=0.5;

% add the required functions to the path:
addpath('/Users/anderssejrhansen/Dropbox/MatLab/Lab/Microscopy/SingleParticleTracking/SoftwarePackages/SLIMFAST_batch_fordist');
addpath('/Users/anderssejrhansen/Dropbox/MatLab/Lab/Microscopy/SingleParticleTracking/SoftwarePackages/SLIMFAST_batch_fordist/bfmatlab');
disp('added paths for MTT algorithm mechanics, bioformats...');

%%%%%%%%%%%%%% READ IN ND2 FILES AND CONVERT TO TIFF FILES %%%%%%%%%%%%%%%%
%disp('-----------------------------------------------------------------');
%disp('reading in nd2 files; writing out MAT workspaces...');
%find all nd2 files:
nd2_files=dir([input_path,'*.nd2']);
Filenames = ''; %for saving the actual file name
temp_struct_for_save = struct;

for iter = 1:length(nd2_files)
    Filenames{iter} = nd2_files(iter).name(1:end-4);
    temp_struct_for_save(iter).blah = [];
end
% open a parallel pool
disp(['reading in ', num2str(length(Filenames)), ' nd2 files, localizing particles and then tracking them']);

parpool('local', min([NumWorkers, length(Filenames)]))
% read in the nd2 file using BioFormats:
parfor iter = 1:length(Filenames)
    %%% read nd2 files:
    img_stack_cell_array = bfopen([input_path, Filenames{iter}, '.nd2']);
    cell_array_2d = img_stack_cell_array{1}; %find pixel vals
    imgs_only_cell_array = cell_array_2d(:,1); % get rid of excess info
    imgs_3d_matrix = cat(3, imgs_only_cell_array{:}); % 3d image matrix
    %convert to double, re-scale to 16 bit:
    imgs_3d_double = (2^16-1)*im2double(imgs_3d_matrix);
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    %%%%%%%%%%%% MTT ALGORITHM PART 1: LOCALIZE ALL PARTICLES %%%%%%%%%%%%%%
    data = localizeParticles_ASH(input_path,impars, locpars, imgs_3d_matrix);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    %%%%%%%%% MTT ALGORITHM PART 2: TRACK PARTICLES BETWEEN FRAMES %%%%%%%%%
    data=buildTracks2_ASH(input_path, data,impars, locpars, trackpars, data.ctrsN, imgs_3d_double);
    temp_struct_for_save(iter).data_cell_array = data.tr;
    temp_struct_for_save(iter).Width = size(imgs_3d_matrix,2);
    temp_struct_for_save(iter).Height = size(imgs_3d_matrix,1);
    temp_struct_for_save(iter).Frames = size(imgs_3d_matrix,3);
end    
% shut down the parallel pool
p = gcp;
delete(p)
toc;
clear save
for iter = 1:length(Filenames)
    disp(['saving MATLAB workspaces for file ', num2str(iter), ' of ', num2str(length(Filenames))]);
    % save meta-data
    settings.Delay = impars.FrameRate;
    settings.px2micron = impars.PixelSize;
    settings.TrackingOptions = trackpars;
    settings.LocOptions = locpars;
    settings.AcquisitionOptions = impars;
    settings.Filename = Filenames{iter};
    settings.Width = temp_struct_for_save(iter).Width;
    settings.Height = temp_struct_for_save(iter).Height;
    settings.Frames = temp_struct_for_save(iter).Frames;
    % It is convenient to store trajectories as a structured array
    trackedPar = struct;
    data_cell_array = temp_struct_for_save(iter).data_cell_array;
    for i=1:length(data_cell_array)
        %convert to nm:
        trackedPar(1,i).xy = 1000 * impars.PixelSize .* data_cell_array{i}(:,1:2);
        trackedPar(i).Frame = data_cell_array{i}(:,3);
        trackedPar(i).TimeStamp = impars.FrameRate.* data_cell_array{i}(:,3);
    end
    %save the output
    save([output_path, Filenames{iter}, '_Tracked.mat'], 'trackedPar', 'settings');
end