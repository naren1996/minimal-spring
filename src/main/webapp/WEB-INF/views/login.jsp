<%@ page contentType="text/html;charset=UTF-8" %>
<!DOCTYPE html>
<html>
<head>
    <title>Login</title>
</head>
<body>
    <h2>Login</h2>

    <% if (request.getParameter("error") != null) { %>
        <p style="color: red;">Invalid username or password.</p>
    <% } %>

    <% if (request.getParameter("logout") != null) { %>
        <p style="color: green;">You have been logged out.</p>
    <% } %>

    <form method="post" action="${pageContext.request.contextPath}/login">
        <label>Username: <input type="text" name="username" /></label><br/><br/>
        <label>Password: <input type="password" name="password" /></label><br/><br/>
        <input type="hidden" name="${_csrf.parameterName}" value="${_csrf.token}" />
        <button type="submit">Log In</button>
    </form>
</body>
</html>
