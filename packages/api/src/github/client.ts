import { config } from "../config.js";
import { HttpError } from "../utils/errors.js";

const GITHUB_API = "https://api.github.com";

const requireToken = () => {
  if (!config.githubPersonalAccessToken) {
    throw new HttpError(
      503,
      "GitHub token not configured: set GH_TOKEN on the api service",
    );
  }
  return config.githubPersonalAccessToken;
};

const githubRequest = async (
  method: string,
  path: string,
  body?: Record<string, unknown>,
) => {
  const response = await fetch(`${GITHUB_API}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${requireToken()}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "dbt-sandbox-api",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  return response;
};

export const projectRepoName = (projectId: string) =>
  `${config.dbtRepoPrefix}${projectId}`;

export const projectRepoUrl = (projectId: string) =>
  `https://github.com/${config.githubOwner}/${projectRepoName(projectId)}`;

export const projectRepoExists = async (projectId: string) => {
  const response = await githubRequest(
    "GET",
    `/repos/${config.githubOwner}/${projectRepoName(projectId)}`,
  );

  if (response.status === 404) {
    return false;
  }

  if (!response.ok) {
    throw new HttpError(502, `GitHub API error: ${response.status}`);
  }

  return true;
};

export const createProjectRepo = async (projectId: string) => {
  const response = await githubRequest(
    "POST",
    `/repos/${config.githubOwner}/${config.githubTemplateRepo}/generate`,
    {
      owner: config.githubOwner,
      name: projectRepoName(projectId),
      description: `dbt project ${projectId} (created by the dbt sandbox)`,
      private: true,
      include_all_branches: false,
    },
  );

  if (!response.ok) {
    const detail = await response
      .json()
      .then((body: { message?: string }) => body?.message)
      .catch(() => undefined);
    throw new HttpError(
      502,
      `GitHub API error creating repo ${projectRepoName(projectId)}: ${response.status}${detail ? ` ${detail}` : ""}`,
    );
  }
};
