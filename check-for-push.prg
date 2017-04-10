* Check files to see if any binary files have changed since the last push.
* If so, run foxbin2prg on those files and push them to git.
* ask for a commit message and commit the push.
* Do this at the start of the program:
DECLARE INTEGER Beep IN WIN32API ;
	INTEGER nFreq, INTEGER nDuration

LOCAL lcData, lcDigest, lnByteCount
LOCAL loCnv as c_foxbin2prg OF "FOXBIN2PRG.PRG" 
SET PROCEDURE TO "foxbin2prg.exe"
loCnv = CREATEOBJECT("c_foxbin2prg") 

CLEAR
? "Check folder for changed files of specific extensions and update them to github"
* use the vfpencryption.fll library to calculate file hashs.
SET LIBRARY TO (LOCFILE("vfpencryption.fll", "FLL"))
SET SAFETY OFF
SET TALK ON
SET DELETED ON
CLEAR

IF !FILE("binFileHash.dbf")
	CREATE TABLE binFileHash FREE (fext c(3), fname c(120), fhash c(15), hashChkd DATETIME, GitTrack l)
	USE binFileHash EXCLUSIVE
	INDEX ON fname TAG fname
	INDEX ON fext + fname TAG fext1
	INDEX on UPPER(fname) TAG upname 
	COPY ALL TO txtFileHash
	USE txtFileHash EXCLUSIVE
	INDEX ON fname TAG fname
	USE
ENDIF

IF !FILE("binExtensions.dbf")
	CREATE TABLE binExtensions FREE (ext c(3), convExt c(3), fb2pext c(3), binonly l, expdata l)
	USE binExtensions EXCLUSIVE
	INDEX ON ext TAG ext
	COPY ALL TO txtExtensions
	APPEND FROM ext.txt TYPE DELIMITED
	USE
	lnAnsw = MESSAGEBOX("You need to set up binary and text extensions to track. Do that now?",4)
	IF lnAnsw = 6
		USE binExtensions
		BROWSE
		MESSAGEBOX("Now set up text extensions",0)
		USE txtExtensions
		BROWSE
		USE
	ENDIF
ENDIF

IF !FILE("fileWork.dbf")
	CREATE TABLE filework FREE (fname c(120))
	USE filework
	USE
ENDIF

IF !FILE("fileChanged.dbf")
	CREATE TABLE fileChanged FREE (fext c(3), fname c(120))
	USE fileChanged EXCLUSIVE
	INDEX ON fname TAG fname
	USE
ENDIF

IF !FILE("pushlist.dbf")
	CREATE TABLE pushlist FREE (fname c(120))
ENDIF


CLOSE DATABASES ALL
USE pushlist
ZAP
SELECT 0
USE fileChanged EXCLUSIVE
ZAP
SELECT 0
USE filework EXCLUSIVE
ZAP
SELECT 0
USE binExtensions
SET ORDER TO ext && ext
SELECT 0
USE binFileHash
* Make sure that file cases match reality... 
! dir *.* /s/b/on > workdir.txt 
SELECT binfilehash 
SET ORDER TO upname && upper(fname) 
SELECT pushlist 
APPEND FROM workdir.txt TYPE SDF 
GO TOP
SCAN
	SELECT binfilehash
	GO TOP  
	SEEK(UPPER(TRIM(pushlist.fname)))
	IF FOUND()
		IF !(ALLTRIM(binfilehash.fname) == ALLTRIM(pushlist.fname))
			REPLACE fname WITH ALLTRIM(pushlist.fname)
		ENDIF 
	ENDIF
	SELECT pushlist
ENDSCAN
SELECT pushlist 
zap
SELECT binfilehash
SET ORDER TO upname && Upper(fname) 
GO TOP 
lnBChanged = 0

SELECT binExtensions
GO TOP
SCAN
	lcExt = binExtensions.ext
	lcConv = binExtensions.convExt
	lcDirCmd = "dir *." + lcExt + " /b /on /s > workdir.txt"
	CLEAR
	@ 2,2 SAY "Working on extension " + lcExt

	@ 4,2 CLEAR
	! "&lcDirCmd"
	SELECT filework
	ZAP
	APPEND FROM workdir.txt TYPE SDF
	*REPLACE ALL fname WITH UPPER(fname)
	IF lcExt = "DBF"
		DELETE FOR "BINEXT" $ upper(fname)
		DELETE FOR "FILEWORK" $ upper(fname)
		DELETE FOR "BINFILEHASH" $ upper(fname)
		DELETE FOR "FILECHANGED" $ upper(fname)
		DELETE FOR "PUSHLIST" $ upper(fname)
		DELETE FOR "TXTFILEHASH" $ upper(fname)
		DELETE FOR "TXTEXTENSIONS" $ upper(fname)
	ENDIF
	GO TOP
	SCAN
		lcFNameW = ALLTRIM(filework.fname)
		@ 4,2 SAY lcFNameW + SPACE(15)
		lcFileHash = STRCONV(HASHFILE(lcFNameW,5), 15)
		SELECT binFileHash
		GO top
		llFound = SEEK(UPPER(lcFNameW))
		IF !llFound
			?? "New file  "
			APPEND BLANK
			REPLACE fname WITH (lcFNameW)
			REPLACE hashChkd WITH DATETIME()
			REPLACE fhash WITH lcFileHash
			REPLACE fext WITH lcExt
			lnAnsw = MESSAGEBOX("New File " + fname + " Track in Git?",36)
			IF lnAnsw = 6 && Yes
				REPLACE GitTrack WITH .T.
				REPLACE fhash WITH "-new-" && So, when we get to the next if, it's different and we regard it as new
			ELSE
				REPLACE GitTrack WITH .F.
			ENDIF
		ENDIF
		IF TRIM(binFileHash.fhash) <> lcFileHash .AND. binFileHash.GitTrack = .T. && The file has changed and we're tracking it.
			?? "File changed  "
			REPLACE hashChkd WITH DATETIME()
			REPLACE fhash WITH lcFileHash
			SELECT fileChanged
			APPEND BLANK
			REPLACE fname WITH lcFNameW, fext WITH lcExt
			lnBChanged = lnBChanged + 1
		ENDIF
		?? SPACE(40)
		SELECT filework
	ENDSCAN
	SELECT binExtensions
ENDSCAN

@ 6,2 SAY "I found " + TRANSFORM(lnBChanged) + " binary files that changed that will be pushed to GIT."


* Now, loop through the changed files and...
* ... if the file extension is one that foxbin2prg doesn't support like .apd...
* ...  ...  rename it to .dbf
* ...  ...  then run foxbin2prg on it
* ...  ...  then rename it back
* ... otherwise, if it is supported, run foxbin2prg on it,
* ... and either way, add the new text file to pushlist.
*
* ... If the file is a database, or if it's an apd or a pjd,
* ... ...  use the file, copy it to a csv and
* ... ...  add the csv to pushlist
IF lnBChanged > 0

	CLOSE DATABASES ALL
	USE pushlist
	SELECT 0
	USE binExtensions
	SET ORDER TO ext   && EXT
	SCAN
		lcExt = ext
		lcConvExt = TRIM(convExt)
		lcFb2pExt = TRIM(fb2pext)
		llBinOnly = binonly
		llExpData = expdata
		@ 8,2 SAY "Checking for changed files of type " + lcExt
		SELECT * FROM fileChanged WHERE fext = lcExt INTO CURSOR bin2text
		IF _TALLY > 0
			SELECT bin2text
			SCAN
				lcFName = TRIM(bin2text.fname )

				* VPME binary files with extensions unknown to foxbin2prg
				* have to be renamed to something else, then bin2prg'ed
				* then renamed back...
				IF lcConvExt > " " && unsupported extension,
					lcNewName = STRTRAN(lcFName,"."+lcExt,"."+lcConvExt)
					lcNewName = STRTRAN(lcFName,"."+LOWER(lcExt),"."+lcConvExt)
					IF FILE(lcNewName)
						DELETE FILE (lcNewName)
					ENDIF
					RENAME (lcFName) TO (lcNewName)
					*lcConvCmd = "foxbin2prg " + lcNewName
					*! "&lcConvCmd"
					RENAME (lcNewName) TO (lcFName)
					lcNewName = STRTRAN(lcNewName, "." + lcConvExt, "." + lcFb2pExt)
					lcNFb2E = LEFT(lcExt,2) + "2"
					lcOFb = STRTRAN(lcNewName, "."  + lcFb2pExt, "." + lcNFb2E)
					DELETE FILE (lcNFb2E) && delete the .xx2 file 
					loCnv.execute( lcNewName ) && create the .xx2 file
					IF FILE(lcOFb)
						DELETE FILE (lcOFb) && get rid of the old .nn2 file
					ENDIF
					RENAME (lcNewName) TO (lcOFb)  && rename the .xx2 to .nn2 
					SELECT pushlist
					APPEND BLANK
					REPLACE fname WITH (lcOFb)
					
				ELSE && OK, good, it is an known extension

					*  Some extensions like FLLs and DLLs can only be stored as
					*  binary blobs, they can't be converted to text and diffed.
					*  if so, we SKIP running foxbin2prg against them. 
 
					IF llBinOnly && DO NOT run foxbin2prg 
						SELECT pushlist
						APPEND BLANK
						REPLACE fname WITH lcNewName
					
					ELSE && NOT Binary only so do a normal fb2p
						* change extension from .xxx to .xx2 
						lcNewName = STRTRAN(lcFName, "." + lcExt, "." + lcFb2pExt)
						lcNewName = STRTRAN(lcFName, "." + LOWER(lcExt), "." + lcFb2pExt)
						DELETE FILE (lcNewName) 
						loCnv.execute( lcFName ) && Run foxbin2prg
						SELECT pushlist
						APPEND BLANK
						REPLACE fname WITH lcNewName
					ENDIF

					* foxbin2prg doesn't export the data of dbf's, only the
					* structure.  We want the data too, so we have to put
					* that somewhere.  So, we make CSVs, but call them CS2
					* for consistancy's sake.
					IF llExpData && Export data of dbf's.
						lcDataFileName = STRTRAN(lcFName, "." + lcExt, ".CS2")
						SELECT 0
						USE (lcFName)
						COPY ALL TO (lcDataFileName) TYPE CSV
						USE
						SELECT pushlist
						APPEND BLANK
						REPLACE fname WITH lcDataFileName
					ENDIF
					SELECT bin2text
				ENDIF
			ENDSCAN
		ENDIF
		SELECT binExtensions
	ENDSCAN

	* Now, we have the binaries we want to push in pushlist as *.xx2 files.
	* So, loop through those, and push each one.
	@ 10,2 SAY "Adding text versions of changed binary files to git."
	CLOSE DATABASES ALL
	USE pushlist
	SET PRINTER TO "pushlist.bat"
	SET CONSOLE OFF
	SET PRINTER ON
	SCAN
		? "git add " + TRIM(pushlist.fname)
	ENDSCAN
	*3? "pause"
	SET PRINTER OFF
	SET PRINTER TO
	SET CONSOLE ON
	! pushlist.bat
	COPY FILE pushlist.bat TO binfiles.txt
ENDIF
? " "
? "Done with Binaries. Now, deal with the non-binarys."
CLOSE DATABASES ALL
USE txtFileHash
SET ORDER TO fname
SELECT 0
USE fileChanged EXCLUSIVE
ZAP
SELECT 0
USE filework EXCLUSIVE
ZAP
SELECT 0
USE pushlist EXCLUSIVE
ZAP
SELECT 0
lnTChanged = 0
USE txtExtensions
GO TOP
SCAN
	lcExt = txtExtensions.ext
	lcDirCmd = "dir *." + lcExt + " /b /on /s > workdir.txt"
	@ 14,2 SAY "Working on extension " + lcExt + SPACE(5)

	@ 16,2 CLEAR
	! "&lcDirCmd"
	SELECT filework
	ZAP
	APPEND FROM workdir.txt TYPE SDF
	* REPLACE ALL fname WITH UPPER(fname)
	DELETE FOR "WORKDIR" $ upper(fname)
	DELETE FOR "PUSHLIST" $ upper(fname)
	GO TOP
	SCAN
		lcFNameW = ALLTRIM(filework.fname)
		@ 16,2 SAY lcFNameW + SPACE(5)
		lcFileHash = STRCONV(HASHFILE(lcFNameW,5), 15)
		SELECT txtFileHash
		GO TOP 
		llFound = SEEK(UPPER(lcFNameW))
		IF !llFound
			?? "New file  "
			APPEND BLANK
			REPLACE fname WITH UPPER(lcFNameW)
			REPLACE hashChkd WITH DATETIME()
			REPLACE fhash WITH lcFileHash
			REPLACE fext WITH lcExt
			lnAnsw = MESSAGEBOX("New File " + fname + " Track in Git?",36)
			IF lnAnsw = 6 && Yes
				REPLACE GitTrack WITH .T.
				REPLACE fhash WITH "-new-" && So, when we get to the next if, it's different and we regard it as new
			ELSE
				REPLACE GitTrack WITH .F.
			ENDIF
		ENDIF
		IF TRIM(txtFileHash.fhash) <> lcFileHash .AND. txtFileHash.GitTrack = .T. && The file has changed and we're tracking it.
			?? "File changed  "
			REPLACE hashChkd WITH DATETIME()
			REPLACE fhash WITH lcFileHash
			SELECT pushlist
			APPEND BLANK
			REPLACE fname WITH lcFNameW
			lnTChanged = lnTChanged + 1
		ENDIF
		?? SPACE(40)
		SELECT filework
	ENDSCAN
	SELECT txtExtensions
ENDSCAN
IF lnTChanged > 0
	* Now, we have the text files we want to push in pushlist
	* So, loop through those, and push each one.
	@ 20,2 SAY "Pushing " + TRANSFORM(lnTChanged) + " text files to git."
	CLOSE DATABASES ALL
	USE pushlist
	SET PRINTER TO "pushlist.bat"
	SET CONSOLE OFF
	SET PRINTER ON
	SCAN
		? "git add " + TRIM(pushlist.fname)
	ENDSCAN
	*? "pause"
	SET PRINTER OFF
	SET PRINTER TO
	SET CONSOLE ON

	? " "
	? " "
	lcCommit = SPACE(60)
	Beep(256,100)
	Beep(400,50)
	Beep(256,100)

	DO WHILE lcCommit = SPACE(60)
		@ 18,2 SAY "Short commit message? x to cancel: " GET lcCommit
		READ
	ENDDO

	IF TRIM(UPPER(lcCommit)) == "X"
		@ 18,2 SAY "Cancel requested."
		RETURN
	ENDIF

	lcCommand = 'git commit -m "' + TRIM(lcCommit) + '"'
	SET PRINTER TO "pushlist.bat" ADDITIVE
	SET CONSOLE OFF
	SET PRINTER ON

	? lcCommand
	? "git push"
	? " "

	SET PRINTER OFF
	SET PRINTER TO
	SET CONSOLE ON

	! pushlist.bat
ELSE
	@ 18,2 SAY "No text files changed. "
ENDIF
IF lnBChanged > 0
	bfBat = FILETOSTR("binfiles.txt")
ELSE
	bfBat = " No changed binary files. "
ENDIF
IF lnTChanged > 0
	tfbat = FILETOSTR("pushlist.bat")
ELSE
	tfbat = " No changed text files."
ENDIF
bfBat = "This is what we found and pushed." +  CHR(13) + CHR(10) + bfBat + CHR(13) + CHR(10) + tfbat
STRTOFILE(bfBat,"CFPaction.txt",0)
MODIFY COMMAND CFPaction.txt
@ 22,2 SAY "Done!"
