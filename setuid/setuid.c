#include <sys/types.h>
#include <unistd.h>

int main(int argc, char **argv) {
    setuid(0);
    char *params[] = {argv[0], argv[1], NULL};
	char *env[] = {NULL};
	execve(argv[0], params, env);
	return 0;
}
