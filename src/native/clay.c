#define CLAY_IMPLEMENTATION
#include "clay.h"
#include <stdio.h>

bool tv_clay_abi(uint32_t command_size, uint32_t config_size, uint32_t error_size) {
	fprintf(stderr, "Clay ABI C/Odin command=%zu/%u config=%zu/%u error=%zu/%u\n",
			sizeof(Clay_RenderCommand), command_size, sizeof(Clay_ElementDeclaration), config_size,
			sizeof(Clay_ErrorData), error_size);
	return command_size == sizeof(Clay_RenderCommand) &&
		   config_size == sizeof(Clay_ElementDeclaration) && error_size == sizeof(Clay_ErrorData);
}
