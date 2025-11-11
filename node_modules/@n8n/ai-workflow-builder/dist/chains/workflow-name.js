"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.workflowNameChain = workflowNameChain;
const prompts_1 = require("@langchain/core/prompts");
const zod_1 = __importDefault(require("zod"));
const workflowNamingPromptTemplate = prompts_1.PromptTemplate.fromTemplate(`Based on the initial user prompt, please generate a name for the workflow that captures its essence and purpose.

<initial_prompt>
{initialPrompt}
</initial_prompt>

This name should be concise, descriptive, and suitable for a workflow that automates tasks related to the given prompt. The name should be in a format that is easy to read and understand. Do not include the word "workflow" in the name.
`);
async function workflowNameChain(llm, initialPrompt) {
    const nameSchema = zod_1.default.object({
        name: zod_1.default.string().min(10).max(128).describe('Name of the workflow based on the prompt'),
    });
    const modelWithStructure = llm.withStructuredOutput(nameSchema);
    const prompt = await workflowNamingPromptTemplate.invoke({
        initialPrompt,
    });
    const structuredOutput = (await modelWithStructure.invoke(prompt));
    return {
        name: structuredOutput.name,
    };
}
//# sourceMappingURL=workflow-name.js.map