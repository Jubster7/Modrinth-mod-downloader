
## Modrinth Mod Downloader (Mac)
### to use:
  - set the version with the '@version' keyword (this must be at the start of the file)
  - put the mod slugs; the part that appears in the url into the mods.txt file, only one per line
    <img width="290" height="40" alt="'sodium' is the mod slug" src="https://github.com/user-attachments/assets/b1b87907-878b-48b6-b575-416ed0b097d9" />
    >here 'sodium' is the mod slug
  - run the shell script
    - the first time you try this it will probably fail as your computer (for a good reason) will not allow you to run random shell scripts you downloaded off of the internet
    - to make this scrip executable you need to run the following commands:
    - `cd /path/to/your/script` `chmod +x modrinth_downloader.sh`
  - this will create a mods folder with all of the mod files inside including any required depencancies
  - copy all of the mods into the mods directory in minecraft
  - if you already have some of the mods downloaed you can move them to the directory mods in the same place as the script and it will not redownload them in order to run faster


### please note:
  - this script meddles with directories so is very not safe and you shouldn't trust it, it also is a shell script so it could fuck your computer if it is coded wrong or malicious
  - this mods folder, the mods.txt file and the are created/used in the same directory as the script, this will not work if they are not in the same directory
  - if there is already a mods folder present in the directory the script will attempt to pull the mods from this folder instead of redownloading it, first the folder will be renamed to oldmods, then it will be moved to the trash directory once the process has completed
  - although i havent tested it probably doesn't work on linux and definitely does not work on windows
  - this app was mostly vibe coded with chat gpt as i dont know the shell syntax (its terrible c style ftw) but it took a lot of back and forth to produce
