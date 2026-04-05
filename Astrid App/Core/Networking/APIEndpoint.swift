import Foundation

enum APIEndpoint {
    // MARK: - Authentication
    case signUpPasswordless(email: String, name: String?)  // Create account without password
    case signInWithApple(identityToken: String, authorizationCode: String, user: String, email: String?, fullName: String?)
    case signInWithGoogle(idToken: String)
    case signOut
    case session
    case mcpToken
    
    // MARK: - Tasks
    case tasks
    case task(id: String)
    case createTask(CreateTaskRequest)
    case updateTask(id: String, UpdateTaskRequest)
    case deleteTask(id: String)
    case completeTask(id: String, completed: Bool)
    case copyTask(id: String)
    case batchCopyTasks(taskIds: [String])
    
    // MARK: - Lists
    case lists
    case list(id: String)
    case createList(CreateListRequest)
    case updateList(id: String, UpdateListRequest)
    case deleteList(id: String)
    case inviteToList(id: String, emails: [String])
    case leaveList(id: String)
    case favoriteList(id: String, favorite: Bool)
    
    // MARK: - Comments
    case taskComments(taskId: String)
    case createComment(taskId: String, CreateCommentRequest)
    case updateComment(id: String, content: String)
    case deleteComment(id: String)
    
    // MARK: - Reminders
    case reminders
    case dismissReminder(id: String)
    case snoozeReminder(id: String, minutes: Int)
    
    // MARK: - Users
    case searchUsers(query: String)
    case searchUsersWithAIAgents(query: String, taskId: String?, listIds: [String]?)
    case userProfile(userId: String)

    // MARK: - Account
    case getAccount
    case updateAccount(UpdateAccountRequest)
    case uploadFile(Data, fileName: String, mimeType: String)
    case verifyEmail(action: String)  // action: "resend", "cancel", "send"
    case deleteAccount(confirmationText: String)
    case exportAccount(format: String)  // format: "json" or "csv"
    
    var path: String {
        switch self {
        case .signUpPasswordless:
            return "/api/auth/mobile-signup"
        case .signInWithApple:
            return "/api/auth/apple"
        case .signInWithGoogle:
            return "/api/auth/google"
        case .signOut:
            return "/api/auth/signout"
        case .session:
            return "/api/auth/mobile-session"
        case .mcpToken:
            return "/api/auth/mobile-mcp-token"
            
        case .tasks:
            return "/api/tasks"
        case .task(let id):
            return "/api/tasks/\(id)"
        case .createTask:
            return "/api/tasks"
        case .updateTask(let id, _):
            return "/api/tasks/\(id)"
        case .deleteTask(let id):
            return "/api/tasks/\(id)"
        case .completeTask(let id, _):
            return "/api/tasks/\(id)"
        case .copyTask(let id):
            return "/api/tasks/\(id)/copy"
        case .batchCopyTasks:
            return "/api/tasks/copy"
            
        case .lists:
            return "/api/lists"
        case .list(let id):
            return "/api/lists/\(id)"
        case .createList:
            return "/api/lists"
        case .updateList(let id, _):
            return "/api/lists/\(id)"
        case .deleteList(let id):
            return "/api/lists/\(id)"
        case .inviteToList(let id, _):
            return "/api/lists/\(id)/invite"
        case .leaveList(let id):
            return "/api/lists/\(id)/leave"
        case .favoriteList(let id, _):
            return "/api/lists/\(id)/favorite"
            
        case .taskComments(let taskId):
            return "/api/tasks/\(taskId)/comments"
        case .createComment(let taskId, _):
            return "/api/tasks/\(taskId)/comments"
        case .updateComment(let id, _):
            return "/api/comments/\(id)"
        case .deleteComment(let id):
            return "/api/comments/\(id)"
            
        case .reminders:
            return "/api/reminders/status"
        case .dismissReminder(let id):
            return "/api/reminders/\(id)/dismiss"
        case .snoozeReminder(let id, _):
            return "/api/reminders/\(id)/snooze"
            
        case .searchUsers, .searchUsersWithAIAgents:
            return "/api/users/search"
        case .userProfile(let userId):
            return "/api/users/\(userId)/profile"

        case .getAccount:
            return "/api/account"
        case .updateAccount:
            return "/api/account"
        case .uploadFile:
            return "/api/upload"
        case .verifyEmail:
            return "/api/account/verify-email"
        case .deleteAccount:
            return "/api/account/delete"
        case .exportAccount:
            return "/api/account/export"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .signUpPasswordless, .signInWithApple, .signInWithGoogle, .mcpToken, .createTask, .createList, .createComment, .copyTask, .batchCopyTasks, .uploadFile, .verifyEmail, .deleteAccount, .leaveList:
            return .post
        case .updateTask, .updateList, .completeTask, .updateComment, .inviteToList, .favoriteList, .snoozeReminder, .dismissReminder, .updateAccount:
            return .put
        case .deleteTask, .deleteList, .deleteComment, .signOut:
            return .delete
        default:
            return .get
        }
    }
    
    func makeRequest(baseURL: URL, encoder: JSONEncoder) throws -> URLRequest {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        
        // Add query parameters
        switch self {
        case .searchUsers(let query):
            urlComponents.queryItems = [URLQueryItem(name: "q", value: query)]
        case .searchUsersWithAIAgents(let query, let taskId, let listIds):
            var items = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "includeAIAgents", value: "true")
            ]
            if let taskId = taskId {
                items.append(URLQueryItem(name: "taskId", value: taskId))
            }
            if let listIds = listIds, !listIds.isEmpty {
                items.append(URLQueryItem(name: "listIds", value: listIds.joined(separator: ",")))
            }
            urlComponents.queryItems = items
        case .verifyEmail(let action):
            urlComponents.queryItems = [URLQueryItem(name: "action", value: action)]
        case .exportAccount(let format):
            urlComponents.queryItems = [URLQueryItem(name: "format", value: format)]
        default:
            break
        }
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios-app", forHTTPHeaderField: "x-platform")

        // Add request body for non-GET requests
        switch self {
        case .signUpPasswordless(let email, let name):
            request.httpBody = try encoder.encode(SignUpPasswordlessRequest(email: email, name: name))

        case .signInWithApple(let identityToken, let authorizationCode, let user, let email, let fullName):
            request.httpBody = try encoder.encode(AppleSignInRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                user: user,
                email: email,
                fullName: fullName
            ))

        case .signInWithGoogle(let idToken):
            request.httpBody = try encoder.encode(GoogleSignInRequest(idToken: idToken))
            
        case .createTask(let taskRequest):
            request.httpBody = try encoder.encode(taskRequest)
            
        case .updateTask(_, let taskRequest):
            request.httpBody = try encoder.encode(taskRequest)
            
        case .completeTask(_, let completed):
            request.httpBody = try encoder.encode(["completed": completed])
            
        case .createList(let listRequest):
            request.httpBody = try encoder.encode(listRequest)
            
        case .updateList(_, let listRequest):
            request.httpBody = try encoder.encode(listRequest)
            
        case .createComment(_, let commentRequest):
            request.httpBody = try encoder.encode(commentRequest)
            
        case .updateComment(_, let content):
            request.httpBody = try encoder.encode(["content": content])
            
        case .inviteToList(_, let emails):
            request.httpBody = try encoder.encode(["emails": emails])
            
        case .favoriteList(_, let favorite):
            request.httpBody = try encoder.encode(["favorite": favorite])
            
        case .snoozeReminder(_, let minutes):
            request.httpBody = try encoder.encode(["minutes": minutes])
            
        case .batchCopyTasks(let taskIds):
            request.httpBody = try encoder.encode(["taskIds": taskIds])

        case .updateAccount(let accountRequest):
            request.httpBody = try encoder.encode(accountRequest)

        case .uploadFile(let data, let fileName, let mimeType):
            // Use multipart/form-data for file uploads
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()

            // Add file data
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = body

        case .deleteAccount(let confirmationText):
            request.httpBody = try encoder.encode(DeleteAccountRequest(confirmationText: confirmationText))

        default:
            break
        }

        return request
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
