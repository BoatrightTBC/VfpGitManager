CLOSE DATABASES ALL
SET SAFETY OFF
SET EXCLUSIVE ON
SET DELETED ON
SET EXACT OFF
*lcCommand = "git pull > pullResult.txt"
*! "&lcCommand"
USE pushlist
ZAP
COPY ALL TO cmdlist
SELECT 0
USE cmdlist
SELECT pushlist
APPEND FROM pullResult.txt TYPE SDF
GO TOP
IF fname = "Already up-to-date."
	MESSAGEBOX("Nothing pulled.  We're done.",0)
	RETURN
ENDIF
lnFileCount = 0
lnFirstFile = 0
DO WHILE !EOF()
	IF "=>" $ fname
* this is a re-name line, nothing for us to do.
	ELSE
* Check to see if the file name ends in "2"
		lcGitLine = STRTRAN(fname," ","") && remove all the spaces
		lnAtBar = AT("|",lcGitLine) - 1
		IF lnAtBar > 0  && there's some file name
			lcFName = ALLTRIM(LEFT(lcGitLine,lnAtBar))
			lnNameLen = LEN(lcFName)
			lcCommand = ""
			IF ".DB2" $ UPPER(lcFName) .OR. ;
					".DC2" $ UPPER(lcFName) .OR. ;
					".FR2" $ UPPER(lcFName) .OR. ;
					".SC2" $ UPPER(lcFName) .OR. ;
					".VC2" $ UPPER(lcFName) .OR. ;
					".MN2" $ UPPER(lcFName) .OR. ;
					".PJ2" $ UPPER(lcFName)
				lcCommand = "foxbin2prg " + lcFName
				INSERT INTO cmdlist ( fname ) VALUES (lcCommand)
			ENDIF
		ENDIF
	ENDIF
	SKIP 
ENDDO
* Now, run all the foxbin2prg's to pull stuff back.
SELECT cmdlist
COPY TO PullBins.bat TYPE SDF 
CLEAR
? "Executing foxbin2prg for imported *.xx2 files." 

! Pullbins.bat

SELECT fname FROM pushlist WHERE ".CS2" $ fname INTO CURSOR lcAppendCur
IF _TALLY > 0
	? "Appending in .CS2 files." 
	SELECT lcAppendCur
	SCAN
		SELECT 0
		lcTable = SUBSTR(UPPER(lcFName), ".CS2","")
		USE (lcTable) EXCLUSIVE
		ZAP
		APPEND FROM lcFName TYPE DELIMITED
		USE
		SELECT lcAppendCur
	ENDSCAN
ENDIF

? "Done." 