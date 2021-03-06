function write_dvh_to_webrtDB(patient_id)
%function write_dvh_to_webrtDB(patient_id)
%
%Input: Writes DVHs for selected structures and doses from global planC to database
%
%APA, 02/27/2011

global planC
indexS = planC{end};


colNamesDVH = {'patient_id', 'structure_edition', 'structure_type', 'dose_calc_mode', 'total_volume', 'min_dose',...
    'mean_dose', 'max_dose', 'number_of_bins', 'dose_id', 'structure_id', 'bin_width'};

colNamesDVHBins = {'dvh_id', 'bin_dose_gy', 'cum_percent_vol', 'cum_cm3_vol'};


%MySQL database (Development)
% conn = database('webCERR_development','root','aa#9135','com.mysql.jdbc.Driver','jdbc:mysql://127.0.0.1/webCERR_development');
conn = database('riview_dev','aptea','aptea654','com.mysql.jdbc.Driver','jdbc:mysql://plmpdb1.mskcc.org/riview_dev');


%Loop over all doses and structures
numStructs = length(planC{indexS.structures});
numDoses = length(planC{indexS.dose});

%Clear old DVHs
planC{indexS.DVH}(:) = [];

for doseNum = 1:numDoses
    
    %get dose-units and convert to gy
    if any(strcmpi(planC{indexS.dose}(doseNum).doseUnits,{'cgy','cgys','cgray','cgrays'}))
        planC{indexS.dose}(doseNum).doseArray = planC{indexS.dose}(doseNum).doseArray * 0.01;
        planC{indexS.dose}(doseNum).doseUnits = 'grays';
    end
    
    %find the dose with dose_uid matching this dose's doseUID from planC
    doseUID = planC{indexS.dose}(doseNum).doseUID;
    sqlq_find_dose = ['select id from doses where dose_uid = ''', doseUID,''''];
    dose_raw = exec(conn, sqlq_find_dose);
    dose = fetch(dose_raw);
    dose = dose.data;
    if ~isstruct(dose)
        continue
    else
        dose_id = dose.id;
    end
    
    %find the structure with structure_uid matching this structures's structUID from planC
    for structNum = 1:numStructs
        
        structS = planC{indexS.structures}(structNum);
        
        %Find matching structure in DB
        sqlq_find_str = ['Select id from structures where structure_uid = ''', structS.strUID,''''];
        str_raw = exec(conn, sqlq_find_str);
        str = fetch(str_raw);
        str = str.Data;
        if ~isstruct(str)
            continue;
        else
            structure_id = str.id;
        end
        
        
        %find the DVH with this dose_id and structure_id
        sqlq_find_dvh = ['Select id from dvhs where (structure_id = ', num2str(structure_id), ' and dose_id = ', num2str(dose_id), ')'];
        whereclause = ['where structure_id = ''', structS.strUID,'''', ' and dose_id = ''', doseUID, ''''];
        dvh_raw = exec(conn, sqlq_find_dvh);
        dvh = fetch(dvh_raw);
        dvh = dvh.Data;
        if ~isstruct(dvh)
            %dvh_id = char(java.util.UUID.randomUUID);
            dvh_id = '';
            isNewRecord = 1;
        else
            dvh_id = dvh.id;
            isNewRecord = 0;
        end
        
        %patient_id
        dvhRecC{1} = patient_id;
        
        %structure_edition
        dvhRecC{2} = NaN;
        
        %structure_type
        dvhRecC{3} = NaN;
        
        %dose_calc_mode
        dvhRecC{4} = '';
        
        %total_volume
        dvhRecC{5} = getStructureVol(structNum,planC);
        
        %min_dose
        dvhRecC{6} = minDose(planC, structNum, doseNum, 'Absolute');
        
        %mean_dose
        dvhRecC{7} = meanDose(planC, structNum, doseNum, 'Absolute');
        
        %max_dose
        dvhRecC{8} = maxDose(planC, structNum, doseNum, 'Absolute');
        
        %Compute cumulative DVH: doseBinsV, cumVols2V, cum_percent_vol
        [planC, doseBinsV, volsHistV] = getDVHMatrix(planC, structNum, doseNum);
        cumVolsV = cumsum(volsHistV);
        cumVols2V  = cumVolsV(end) - cumVolsV;  %cumVolsV is the cumulative volume lt that corresponding dose including that dose bin.
        cum_percent_vol = cumVols2V/cumVolsV(end)*100;
        
        %number_of_bins
        dvhRecC{9} = length(doseBinsV);
        
        %dose_id
        dvhRecC{10} = dose_id;
        
        %structure_id
        dvhRecC{11} = structure_id;
                
        %bin_width
        dvhRecC{12} = mean(diff(doseBinsV));
        
        if isNewRecord
            insert(conn,'dvhs',colNamesDVH,dvhRecC);
            % get dvh_id with this dose_id and structure_id
            sqlq_find_dvh = ['Select id from dvhs where (structure_id = ', num2str(structure_id), ' and dose_id = ', num2str(dose_id), ')'];
            dvh_raw = exec(conn, sqlq_find_dvh);
            dvh = fetch(dvh_raw);
            dvh = dvh.Data;
            dvh_id = dvh.id;
        else
            %dvh_id
            dvhNewRecC = dvhRecC;
            dvhNewRecC{end+1} = dvh_id;            
            update(conn,'dvhs',[colNamesDVH, 'id'],dvhNewRecC,whereclause);
            %Find dvh_bins which match this dvh and delete them
            sqlq_delete_dvh_bins = ['delete from dvh_bins where dvh_id = ', num2str(dvh_id)];
            dvh_bins_delete = exec(conn, sqlq_delete_dvh_bins);
        end
        
        %write dvh_bins
        numBins = length(doseBinsV);
        for binNum = 1:numBins
            dvhBinsRecC{1} = dvh_id;
            dvhBinsRecC{2} = doseBinsV(binNum);
            dvhBinsRecC{3} = cum_percent_vol(binNum);
            dvhBinsRecC{4} = cumVols2V(binNum);
            insert(conn,'dvh_bins',colNamesDVHBins,dvhBinsRecC);
            pause(0.001)
        end
        
    end %structures
    
end %doses

