/* Drop uid 0 (Haiku's desk user) and exec a command as another account.
 * pg_resetwal refuses euid 0, and su on this guest will not switch. */
#include <pwd.h>
#include <stdio.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
	struct passwd *pw;

	if (argc < 3) {
		fprintf(stderr, "usage: haiku_runas user command [args]\n");
		return 2;
	}
	pw = getpwnam(argv[1]);
	if (pw == NULL) {
		perror(argv[1]);
		return 1;
	}
	if (setgid(pw->pw_gid) != 0 || setuid(pw->pw_uid) != 0) {
		perror("setuid");
		return 1;
	}
	execvp(argv[2], argv + 2);
	perror(argv[2]);
	return 1;
}
