function filenames=GetFilenames(directory,extension);
% filenames=GetFilenames(directory,extension);
% Uses the "dir" and "diary" commands to obtain a list of files
% with the given extension, e.g. '.m'. Returns a string matrix
% with one filename per row. 
%
% GetFilenames() assumes that each filename ends at the first instance
% of the specified extension followed by a space, e.g. '.m '. You may 
% give a null extension, '', to list all files, but then GetFilenames() 
% will incorrectly parse any filenames that include spaces. 
% E.g. 'my first program.m' would be listed as 3 files: 'my', 'first', 
% and 'program.m'.
%
% filenames=GetFilenames(pwd,'.m');
%
% WARNING: Deletes file 'diarytmp.tmp' if it exists in the given directory.
%
% ACKNOWLEDGEMENT: In writing this code, I was greatly helped by examining 
% I. Kollar's listfils.m in the "names" Toolbox on the MathWorks web site.
%
% Denis Pelli 5/14/96
%
% 5/14/96  dgp  Changed definition of "extension" to include the period '.'
% 5/15/96  dhb  Got rid of row of spaces.
% 5/15/96 dgp fixed the quote doubling code
% 6/6/96 dgp cosmetic

c=computer;
pathsep = ':';	% path separator character
dirsep = '/';	% directory separator character
if strcmp(c(1:2),'PC')
	pathsep = ';'; dirsep = '\';
elseif strcmp(c(1:2),'MA')
%    pathsep = ';'; dirsep = ':';
    pathsep = ';'; dirsep = '/';
%elseif isvms
%	pathsep = ','; dirsep='.';
end

% Use "dir" and "diary" to get a listing of directory.
% Unfortunately this listing includes multiple files per line.
% We save the result in "filestr" as one long string.
% Note that the list will include 'diaryTmp.tmp' even
% though that file is deleted immediately after we make
% the list.
DiaryStatus=get(0,'Diary');
DiaryFile=get(0,'DiaryFile');
diary off
if exist('diarytmp.tmp'), delete diarytmp.tmp, end
% double any quote characters
quote='''';
for i=fliplr(findstr(directory,quote))
	directory=directory([1:i i:length(directory)]);
end
diary diarytmp.tmp
eval(['dir ' quote deblank(directory) dirsep '*' extension quote]);
diary off
set(0,'DiaryFile',DiaryFile) %Restore diary file name
set(0,'Diary',DiaryStatus)
fid=fopen('diarytmp.tmp','r'); filestr=fread(fid); fclose(fid);
delete diarytmp.tmp
filestr=setstr(filestr');

% Extract the individual filenames, and save them, one per row,
% in "filenames".
% This is tricky because dir separates the filenames by spaces,
% yet Macintosh filenames may include spaces.
% As a pretty good solution, we assume that the filename ends
% at the first instance of the specified extension
% followed by a space, e.g. '.m '. This will work fine with a file 
% called 'my first program.m', but will incorrectly parse the name 
% 'mm.m good.m' as two files because it includes '.m ' in the middle
% of the name.
% Alas, this rule doesn't work so well when the specified extension
% is null, '', because then the filenames will be considered to end
% at the first space, e.g. 'my first program.m' would be listed
% as 3 files 'my', 'first', and 'program.m'.
cr=setstr(13); lf=setstr(10);
indcr=find((filestr==cr)|(filestr==lf));
if ~isempty(filestr)
	filestr(indcr)=cr(ones(size(indcr)));
end
indcr=[0,indcr];
filenames=[];
for l=2:length(indcr)
	oneLine=filestr(indcr(l-1)+1:indcr(l)-1);
	%%fprintf('>>"%s"\n',oneLine);
	nameBegin=find(~( (oneLine==' ')|((oneLine>=9)&(oneLine<=13)) )); % index of first printing char
	while ~isempty(nameBegin)
		if(nameBegin(1)>1)
			oneLine(1:nameBegin(1)-1)='';
		end
		nameEnd=min([length(oneLine),findstr(oneLine,[extension ' '])+length(extension)-1]);
		fname=oneLine(1:nameEnd);
		if(strcmp(fname,'diarytmp.tmp'))
			fname='';
		end
		%%fprintf('"%s"\n',fname);
		if (~isempty(fname) & strcmp(fname,'') ~= 1)
			filenames=str2mat(filenames,fname);
		end
		oneLine(1:nameEnd)='';
		nameBegin=find(~( (oneLine==' ')|((oneLine>=9)&(oneLine<=13)) )); % index of first printing char
	end
end

% Get rid of line of spaces that was created at the start of filenames
if (size(filenames,1) == 1)
	filenames = [];
else
	filenames = filenames(2:size(filenames,1),:);
end

