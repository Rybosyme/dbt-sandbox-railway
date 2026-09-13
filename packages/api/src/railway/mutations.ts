export const serviceCreateMutation = `
  mutation serviceCreate($input: ServiceCreateInput!) {
    serviceCreate(input: $input) {
      id
    }
  }
`;

export const serviceDeleteMutation = `
  mutation serviceDelete($id: String!) {
    serviceDelete(id: $id)
  }
`;

export const serviceInstanceDeployMutation = `
  mutation serviceInstanceDeploy($serviceId: String!, $environmentId: String!) {
    serviceInstanceDeployV2(serviceId: $serviceId, environmentId: $environmentId)
  }
`;
