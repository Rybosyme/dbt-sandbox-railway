import { eq, desc } from "drizzle-orm";
import { randomUUID } from "crypto";

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
};

const generateSessionName = () => `sandbox-${Date.now()}`;

// Each session gets its own dbt target schema so concurrent sandboxes never collide.
const schemaForSession = (sessionName: string) => {
  const slug = sessionName.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return `dbt_${slug}`.slice(0, 63);
};

export const createSession = async ({ name }: CreateSessionInput) => {
  if (config.localMode) {
    throw new HttpError(403, "Session creation disabled in local mode");
  }

  const resolvedName = name?.trim() ? name.trim() : generateSessionName();
  const sandboxVariables: Record<string, string> = {
    ...config.sandboxVars,
    DBT_SCHEMA: schemaForSession(resolvedName),
  };

  if (config.sandboxRepoUrl) {
    sandboxVariables.SANDBOX_REPO_URL = config.sandboxRepoUrl;
  }

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
    });
  } catch (error) {
    await db
      .update(sessions)
      .set({ status: session.status, updatedAt: new Date() })
      .where(eq(sessions.id, id));
    throw error;
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
