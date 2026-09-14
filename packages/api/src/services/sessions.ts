import { eq, desc } from "drizzle-orm";
import { randomBytes, randomUUID } from "crypto";

import { config } from "../config.js";
import { db } from "../db/client.js";
import { sessions } from "../db/schema.js";
import { railwayRequest } from "../railway/client.js";
import {
  serviceCreateMutation,
  serviceDeleteMutation,
  serviceInstanceDeployMutation,
} from "../railway/mutations.js";
import { HttpError } from "../utils/errors.js";
import {
  createProjectRepo,
  projectRepoExists,
  projectRepoName,
  projectRepoUrl,
} from "../github/client.js";

type ServiceCreateResponse = {
  serviceCreate: {
    id: string;
  };
};

type ServiceInstanceDeployResponse = {
  serviceInstanceDeployV2: string;
};

type ServiceDeleteResponse = {
  serviceDelete: boolean;
};

export type CreateSessionInput = {
  name?: string;
  dbtProjectId?: string;
};

const PROJECT_ID_PATTERN = /^[A-Z0-9][A-Z0-9-]{1,30}$/;

// Short, all-caps IDs without look-alike characters (no 0/O, 1/I/L).
const ID_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const ID_LENGTH = 5;

const generateShortId = () =>
  Array.from(randomBytes(ID_LENGTH), (b) => ID_ALPHABET[b % ID_ALPHABET.length]).join("");

const generateSessionName = async (projectId: string) => {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const candidate = `${projectRepoName(projectId)}-${generateShortId()}`;
    const [existing] = await db
      .select({ id: sessions.id })
      .from(sessions)
      .where(eq(sessions.name, candidate));
    if (!existing) {
      return candidate;
    }
  }
  throw new HttpError(500, "Could not allocate a unique session name");
};

// Every session of a project builds into the same schema, like a shared dbt dev target.
const schemaForProject = (projectId: string) =>
  `dbt_${projectId.toLowerCase().replace(/[^a-z0-9]+/g, "_")}`.slice(0, 63);

export const createSession = async ({
  name,
  dbtProjectId,
}: CreateSessionInput) => {
  if (config.localMode) {
    throw new HttpError(403, "Session creation disabled in local mode");
  }

  // Resolve the dbt project: reuse an existing repo or create one from the template.
  let projectId: string;
  if (dbtProjectId?.trim()) {
    projectId = dbtProjectId.trim().toUpperCase();
    if (!PROJECT_ID_PATTERN.test(projectId)) {
      throw new HttpError(400, "Invalid dbt project id");
    }
    if (!(await projectRepoExists(projectId))) {
      throw new HttpError(
        404,
        `dbt project ${projectId} not found (${projectRepoUrl(projectId)})`,
      );
    }
  } else {
    projectId = generateShortId();
    while (await projectRepoExists(projectId)) {
      projectId = generateShortId();
    }
    await createProjectRepo(projectId);
  }

  const resolvedName = name?.trim()
    ? name.trim()
    : await generateSessionName(projectId);
  const sandboxVariables: Record<string, string> = {
    ...config.sandboxVars,
    SANDBOX_REPO_URL: `${projectRepoUrl(projectId)}.git`,
    DBT_PROJECT_ID: projectId,
    DBT_SCHEMA: schemaForProject(projectId),
  };

  if (config.githubPersonalAccessToken) {
    sandboxVariables.GH_TOKEN = config.githubPersonalAccessToken;
  }

  const serviceCreateInput: Record<string, unknown> = {
    projectId: config.railwayProjectId,
    environmentId: config.railwayEnvironmentId,
    name: resolvedName,
    source: {
      image: config.railwayServiceImage,
    },
  };

  if (Object.keys(sandboxVariables).length > 0) {
    serviceCreateInput.variables = sandboxVariables;
  }

  const data = await railwayRequest<ServiceCreateResponse>(
    serviceCreateMutation,
    {
      input: serviceCreateInput,
    },
  );

  if (!data.serviceCreate?.id) {
    throw new HttpError(502, "Railway API error: missing service id");
  }

  // serviceCreate does not always start a deployment (e.g. when authenticated
  // with a project token), so trigger one explicitly. Roll back on failure.
  try {
    await railwayRequest<ServiceInstanceDeployResponse>(
      serviceInstanceDeployMutation,
      {
        serviceId: data.serviceCreate.id,
        environmentId: config.railwayEnvironmentId,
      },
    );
  } catch (error) {
    await railwayRequest<ServiceDeleteResponse>(serviceDeleteMutation, {
      id: data.serviceCreate.id,
      environmentId: config.railwayEnvironmentId,
    }).catch(() => undefined);
    throw error;
  }

  const id = randomUUID();
  const now = new Date();

  const [session] = await db
    .insert(sessions)
    .values({
      id,
      name: resolvedName,
      status: "starting",
      railwayServiceId: data.serviceCreate.id,
      dbtProjectId: projectId,
      createdAt: now,
      updatedAt: now,
    })
    .returning();

  return session;
};

export const listSessions = async () =>
  db.select().from(sessions).orderBy(desc(sessions.createdAt));

export const getSession = async (id: string) => {
  const [session] = await db.select().from(sessions).where(eq(sessions.id, id));

  if (!session) {
    throw new HttpError(404, "Session not found");
  }

  return session;
};

export const deleteSession = async (id: string) => {
  const session = await getSession(id);

  if (session.status === "deleted") {
    return session;
  }

  const [terminating] = await db
    .update(sessions)
    .set({
      status: "terminating",
      updatedAt: new Date(),
    })
    .where(eq(sessions.id, id))
    .returning();

  try {
    await railwayRequest<ServiceDeleteResponse>(serviceDeleteMutation, {
      id: session.railwayServiceId,
      environmentId: config.railwayEnvironmentId,
    });
  } catch (error) {
    const alreadyGone =
      error instanceof HttpError && /not found/i.test(error.message);
    if (!alreadyGone) {
      await db
        .update(sessions)
        .set({ status: session.status, updatedAt: new Date() })
        .where(eq(sessions.id, id));
      throw error;
    }
  }

  const [updated] = await db
    .update(sessions)
    .set({
      status: "deleted",
      updatedAt: new Date(),
    })
    .where(eq(sessions.id, id))
    .returning();

  return updated;
};
