const std = @import("std");
const testing = std.testing;
const googleai = @import("google-generative-ai");
const rocketchat = @import("rocketchat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const api_key = try getEnv(allocator, "GOOGLE_AI_APIKEY");
    const host = try getEnv(allocator, "RC_HOST");
    const username = try getEnv(allocator, "RC_USER");
    const password = try getEnv(allocator, "RC_PASSWORD");
    const roomName = try getEnv(allocator, "RC_ROOM");
    const syspromptPath = try getEnv(allocator, "SYSTEMPROMPT");

    const absSysPromptPath = try std.fs.realpathAlloc(allocator, syspromptPath);
    var syspromptF = try std.fs.openFileAbsolute(absSysPromptPath, .{ .mode = .read_only });
    const sysprompt = try syspromptF.readToEndAlloc(allocator, 4 * 1024 * 1024);

    const genAI = googleai.GoogleGenerativeAI.init(api_key);
    const model = genAI.getGenerativeModel("gemini-2.0-flash");

    var session = model.startChat(allocator);
    defer session.deinit();

    _ = try session.sendMessage(sysprompt);

    var client = try rocketchat.RC.init(allocator, .{
        .port = 443, // 3000,
        .host = host,
        .tls = true,
    });
    defer client.deinit();

    try client.connect();
    try client.startLoop();

    try client.login(username, password);
    try client.subscribeToMessages();
    const roomId = try client.getRoomId(roomName);
    try client.joinRoom(roomId);

    while (true) {
        const message = client.messages.wait();

        if (!std.mem.eql(u8, message.rid, roomId)) {
            return;
        }

        if (std.mem.indexOfScalar(u8, message.msg, '?')) |_| {
            const response = try session.sendMessage(message.msg);
            const responseCopy = try client.allocator.dupe(u8, response);
            defer client.allocator.free(responseCopy);
            try client.sendToRoomId(responseCopy, roomId);
        }
    }
}

fn getEnv(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| {
        std.debug.panic("env var {s} must be set", .{name});
        return err;
    };
}
