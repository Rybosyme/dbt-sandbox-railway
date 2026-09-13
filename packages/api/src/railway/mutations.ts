export const serviceCreateMutation = `
  mutation serviceCreate($input: ServiceCreateInput!) {
    serviceCreate(input: $input) {
      id
    }
  }
`;

// environmentId is required for project-token auth to be authorized.
export const serviceDeleteMutation = `
  mutation serviceDelete($id: String!, $environmentId: String!) {
    serviceDelete(id: $id, environmentId: $environmentId)
  }
`;

export const serviceInstanceDeployMutation = `
  mutation serviceInstanceDeploy($serviceId: String!, $environmentId: String!) {
    serviceInstanceDeployV2(serviceId: $serviceId, environmentId: $environmentId)
  }
`;
