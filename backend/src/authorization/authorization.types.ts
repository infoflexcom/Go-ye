export interface AuthenticatedActor {
  id: string;
  sessionId: string;
  roles: string[];
  homeUnitId?: string;
  homePath?: string;
  isGlobalAdmin: boolean;
}
