const requiredEnv = (name: string): string => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
};

const parseSandboxLocalMap = (value?: string) => {
  if (!value) {
    return {};
  }

  return value.split(",").reduce<Record<string, string>>((acc, entry) => {
    const [key, target] = entry.split("=");
    if (!key || !target) {
      return acc;
    }

    acc[key.trim()] = target.trim();
    return acc;
  }, {});
};

const SANDBOX_VAR_PREFIX = "SANDBOX_VAR_";

// Any API env var named SANDBOX_VAR_<NAME> is injected into every sandbox as <NAME>.
const parseSandboxVars = () =>
  Object.entries(process.env).reduce<Record<string, string>>((acc, [key, value]) => {
    if (key.startsWith(SANDBOX_VAR_PREFIX) && value) {
      acc[key.slice(SANDBOX_VAR_PREFIX.length)] = value;
    }
    return acc;
  }, {});

const railwayProjectToken = process.env.RAILWAY_PROJECT_TOKEN;
const railwayApiToken = process.env.RAILWAY_API_TOKEN;

if (!railwayProjectToken && !railwayApiToken) {
  console.warn(
    "RAILWAY_PROJECT_TOKEN / RAILWAY_API_TOKEN not set: sessions cannot be created until one is configured",
  );
}

export const config = {
  nodeEnv: process.env.NODE_ENV ?? "development",
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: requiredEnv("DATABASE_URL"),
  railwayApiToken,
  railwayProjectToken,
  railwayProjectId: requiredEnv("RAILWAY_PROJECT_ID"),
  railwayEnvironmentId: requiredEnv("RAILWAY_ENVIRONMENT_ID"),
  railwayServiceImage: requiredEnv("RAILWAY_SERVICE_IMAGE"),
  railwayGraphqlUrl:
    process.env.RAILWAY_GRAPHQL_URL ?? "https://backboard.railway.app/graphql/v2",
  adminPassword: requiredEnv("ADMIN_PASSWORD"),
  authTokenSecret: requiredEnv("AUTH_TOKEN_SECRET"),
  webOrigin: process.env.WEB_ORIGIN,
  apiDirectHost: process.env.API_DIRECT_HOST ?? "localhost",
  apiProxyHost: process.env.API_PROXY_HOST ?? "proxy.localhost",
  sandboxInternalDomain:
    process.env.SANDBOX_INTERNAL_DOMAIN ?? "railway.internal",
  sandboxPort: Number(process.env.SANDBOX_PORT ?? 8080),
  sandboxLocalBaseUrl: process.env.SANDBOX_LOCAL_BASE_URL,
  sandboxLocalMap: parseSandboxLocalMap(process.env.SANDBOX_LOCAL_MAP),
  sandboxRepoUrl: process.env.SANDBOX_REPO_URL,
  sandboxVars: parseSandboxVars(),
  githubPersonalAccessToken: process.env.GH_TOKEN,
  githubOwner: process.env.GITHUB_OWNER ?? "Rybosyme",
  githubTemplateRepo: process.env.GITHUB_TEMPLATE_REPO ?? "dbt-project-template",
  dbtRepoPrefix: process.env.DBT_REPO_PREFIX ?? "dbt-",
  localMode:
    process.env.LOCAL_MODE === "true" ||
    ((process.env.SANDBOX_LOCAL_BASE_URL || process.env.SANDBOX_LOCAL_MAP) &&
      (process.env.NODE_ENV ?? "development") !== "production"),
};
