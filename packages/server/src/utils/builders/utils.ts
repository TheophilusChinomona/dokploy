import { dirname, join } from "node:path";
import { encodeBase64, prepareEnvironmentVariables } from "../docker/utils";

export const createEnvFileCommand = (
	directory: string,
	env: string | null,
	projectEnv?: string | null,
	environmentEnv?: string | null,
) => {
	const envFileContent = prepareEnvironmentVariables(
		env,
		projectEnv,
		environmentEnv,
	).join("\n");

	// Skip creating the .env file when there are no variables — an empty file
	// causes path doubling in Docker builds (the build context path appears twice
	// in the COPY instruction, resulting in a "file not found" build error).
	if (!envFileContent) return "";

	const encodedContent = encodeBase64(envFileContent);
	const envFilePath = join(dirname(directory), ".env");

	return `echo "${encodedContent}" | base64 -d > "${envFilePath}";`;
};
