#include <sys/types.h>
#include <unistd.h>
int main(int argc, char **argv) {
    setuid(0);
	execve(argv[1], (argc > 1) ? argv+1 : 0, 0);
	return 0;
}
