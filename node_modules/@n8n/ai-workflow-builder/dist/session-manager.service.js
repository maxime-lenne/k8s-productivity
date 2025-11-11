"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var SessionManagerService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SessionManagerService = void 0;
const langgraph_1 = require("@langchain/langgraph");
const backend_common_1 = require("@n8n/backend-common");
const di_1 = require("@n8n/di");
const stream_processor_1 = require("./utils/stream-processor");
const builder_tools_1 = require("./tools/builder-tools");
const sessions_1 = require("./types/sessions");
let SessionManagerService = SessionManagerService_1 = class SessionManagerService {
    parsedNodeTypes;
    logger;
    checkpointer;
    constructor(parsedNodeTypes, logger) {
        this.parsedNodeTypes = parsedNodeTypes;
        this.logger = logger;
        this.checkpointer = new langgraph_1.MemorySaver();
    }
    static generateThreadId(workflowId, userId) {
        return workflowId
            ? `workflow-${workflowId}-user-${userId ?? new Date().getTime()}`
            : crypto.randomUUID();
    }
    getCheckpointer() {
        return this.checkpointer;
    }
    async getSessions(workflowId, userId) {
        const sessions = [];
        if (workflowId) {
            const threadId = SessionManagerService_1.generateThreadId(workflowId, userId);
            const threadConfig = {
                configurable: {
                    thread_id: threadId,
                },
            };
            try {
                const checkpoint = await this.checkpointer.getTuple(threadConfig);
                if (checkpoint?.checkpoint) {
                    const rawMessages = checkpoint.checkpoint.channel_values?.messages;
                    const messages = (0, sessions_1.isLangchainMessagesArray)(rawMessages)
                        ? rawMessages
                        : [];
                    sessions.push({
                        sessionId: threadId,
                        messages: (0, stream_processor_1.formatMessages)(messages, (0, builder_tools_1.getBuilderToolsForDisplay)({
                            nodeTypes: this.parsedNodeTypes,
                        })),
                        lastUpdated: checkpoint.checkpoint.ts,
                    });
                }
            }
            catch (error) {
                this.logger?.debug('No session found for workflow:', { workflowId, error });
            }
        }
        return { sessions };
    }
};
exports.SessionManagerService = SessionManagerService;
exports.SessionManagerService = SessionManagerService = SessionManagerService_1 = __decorate([
    (0, di_1.Service)(),
    __metadata("design:paramtypes", [Array, backend_common_1.Logger])
], SessionManagerService);
//# sourceMappingURL=session-manager.service.js.map