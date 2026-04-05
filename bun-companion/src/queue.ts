import { createServer } from "node:net";
import { logger as baseLogger } from "./logger";
import { exitWithPause } from "./utils";

export interface CreateAndStartPipeServerOptions {
  shouldPopQueueRandomly: boolean;
}

export interface QueueEntry {
  displayName: string;
  showNameAboveHead: boolean;
}

const COMMAND_POP = "POP";
const PIPE_PATH = "\\\\.\\pipe\\RetroRewindCompanion";

const logger = baseLogger.getSubLogger({ name: "Queue" });
export const namesQueue: QueueEntry[] = [];

export function createAndStartPipeServer({ shouldPopQueueRandomly }: CreateAndStartPipeServerOptions) {
  logger.info("Should Pop Randomly? ", shouldPopQueueRandomly);

  const pipeServer = createServer((connection) => {
    connection.on("data", (data) => {
      const command = data.toString().trim();

      if (command === COMMAND_POP) {
        const queueEntry = popQueueEntry(shouldPopQueueRandomly);

        if (queueEntry) {
          logger.info(`Sent "${queueEntry.displayName}" to game (${namesQueue.length} remaining)`);
          connection.write(JSON.stringify(queueEntry) + "\n");
        } else {
          connection.write("\n");
        }
      } else {
        logger.warn(`Unknown pipe command received: ${command}, skipping...`);
      }
    });

    connection.on("error", (err) => {
      logger.warn(`Pipe connection error: ${err.message}`);
    });
  });

  pipeServer.on("error", async (err) => {
    logger.error(`Pipe server error: ${err.message}`);
    return await exitWithPause(1);
  });

  pipeServer.listen(PIPE_PATH, () => {
    logger.info(`Named pipe server is listening on ${PIPE_PATH}`);
  });
}

function popQueueEntry(shouldPopQueueRandomly: boolean): QueueEntry | null | undefined {
  if (namesQueue.length === 0) {
    return null;
  }

  if (shouldPopQueueRandomly) {
    const randomIndex = Math.floor(Math.random() * namesQueue.length);
    return namesQueue.splice(randomIndex, 1)[0];
  }

  return namesQueue.shift();
}
