import type { BaseChatModel } from '@langchain/core/language_models/chat_models';
export declare function workflowNameChain(llm: BaseChatModel, initialPrompt: string): Promise<{
    name: string;
}>;
