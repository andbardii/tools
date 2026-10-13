// Browser facade: persistence lives behind the local HTTP API.
import { apiClient } from './api';
export const db = apiClient;
export const dbService = apiClient;
