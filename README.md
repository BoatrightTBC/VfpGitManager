# VfpGitManager
Automate pushing and pulling of binary and text files for VFP projects to and from git repositorues

these programs use a local database co-located with the project to store a hash for each binary file in the project.  

When check-for-push is run, it compares the current hash of the binary file to the stored hash, and if it has changed, it runs foxbin2prg to create a text format file and adds it to a batch file that pushes the changed text files to git. 

When the program encounters a new file in the project directory, it asks if you want to track that file in git.  If not, the program skips over it when checking for changes. 

after completing checks, it asks for a commit message, adds, commits and pushes. 

Check-for-pull does the inverse. 

The project includes a proposed .gitignore and proposed lists of extensions to track. 

It requires a copy of foxbin2prg.exe. 
