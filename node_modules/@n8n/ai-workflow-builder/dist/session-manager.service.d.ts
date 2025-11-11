import { MemorySaver } from '@langchain/langgraph';
import { Logger } from '@n8n/backend-common';
import type { INodeTypeDescription } from 'n8n-workflow';
import { Session } from './types/sessions';
export declare class SessionManagerService {
    private readonly parsedNodeTypes;
    private readonly logger?;
    private checkpointer;
    constructor(parsedNodeTypes: INodeTypeDescription[], logger?: Logger | undefined);
    static generateThreadId(workflowId?: string, userId?: string): string;
    getCheckpointer(): MemorySaver;
    getSessions(workflowId: string | undefined, userId: string | undefined): Promise<{
        sessions: Session[];
    }>;
}
