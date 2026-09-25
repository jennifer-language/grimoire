# How the dates are found

`git log -1` per chapter, for the committer date and the subject line. The
filesystem is not asked: a fresh checkout stamps every file with the moment it
was cloned, which would publish a feed claiming the whole book changed today.
