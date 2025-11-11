import type { BaseChatModel } from '@langchain/core/language_models/chat_models';
import type { Logger } from '@n8n/backend-common';
import type { INodeTypeDescription } from 'n8n-workflow';
import type { BuilderTool, BuilderToolBase } from '../utils/stream-processor';
export declare function getBuilderTools({ parsedNodeTypes, logger, llmComplexTask, instanceUrl, }: {
    parsedNodeTypes: INodeTypeDescription[];
    llmComplexTask: BaseChatModel;
    logger?: Logger;
    instanceUrl?: string;
}): BuilderTool[];
export declare function getBuilderToolsForDisplay({ nodeTypes, }: {
    nodeTypes: INodeTypeDescription[];
}): BuilderToolBase[];
