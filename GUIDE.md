# Minimal Spring + Spring Security on Tomcat: A Step-by-Step Guide

This guide walks you through building a minimal **Spring Framework** (not Spring Boot) web application with **Spring Security**, deployed to **Apache Tomcat**. Every file is explained — what it does, why it exists, and how it connects to the rest.

## What Are We Building?

A web application with:
- A **secured home page** (`/`) that only logged-in users can see
- A **login page** (`/login`) with a username/password form
- **Spring Security** protecting all pages and handling authentication
- **WAR packaging** so Tomcat can deploy and run it

Spring Boot normally hides all the wiring behind auto-configuration. Here, we do every piece manually so you can see exactly what happens.

---

## Prerequisites

| Tool | Minimum Version | Why |
|------|----------------|-----|
| **Java JDK** | 17+ | Spring 6 requires Java 17 as its baseline |
| **Apache Maven** | 3.8+ | Build tool that compiles, packages, and manages dependencies |
| **Apache Tomcat** | **10.1+** | Must be 10.1+ because Spring 6 uses `jakarta.*` namespaces (Tomcat 9 uses the old `javax.*` and will NOT work) |

---

## Project Structure

```
minimal-spring/
├── GUIDE.md                        ← You are here
├── pom.xml                         ← Maven build configuration
└── src/main/
    ├── java/com/example/
    │   ├── AppInitializer.java     ← Replaces web.xml (Servlet 3.0+ entry point)
    │   ├── config/
    │   │   ├── AppConfig.java      ← Root application context
    │   │   ├── WebConfig.java      ← Spring MVC configuration
    │   │   ├── SecurityConfig.java ← Spring Security rules
    │   │   └── SecurityInitializer.java ← Registers security filters
    │   └── controller/
    │       └── HomeController.java ← HTTP endpoints
    └── webapp/WEB-INF/views/
        ├── home.jsp                ← Secured home page
        └── login.jsp               ← Login form
```

---

## Step 1: Create `pom.xml` — Define the Project and Its Dependencies

**What we're achieving:** Tell Maven how to build our project, what libraries we need, and that the output should be a `.war` file (not a `.jar`).

### Key elements explained

**`<packaging>war</packaging>`** — Without this, Maven defaults to JAR packaging. A WAR (Web Application Archive) is the format Tomcat expects. It bundles your classes, libraries, and web resources (JSPs, static files) into a single deployable archive.

**Dependencies (6 total):**

| Dependency | Purpose |
|-----------|---------|
| `spring-webmvc` | The Spring MVC framework. This single dependency transitively pulls in `spring-core`, `spring-context`, `spring-beans`, and `spring-web` — everything needed for a web application. |
| `spring-security-web` | The servlet filter chain that intercepts every HTTP request to enforce security. |
| `spring-security-config` | Provides `@EnableWebSecurity` and the Java DSL for configuring security rules. |
| `jakarta.servlet-api` | The Servlet API that Tomcat implements. Scope is **`provided`** because Tomcat already contains this at runtime — including it in the WAR would cause conflicts. |
| `jakarta.servlet.jsp.jstl-api` | JSTL tag library API for JSP views. |
| `jakarta.servlet.jsp.jstl` (glassfish) | JSTL implementation. |

**`maven-war-plugin` with `failOnMissingWebXml=false`** — Since we use Java-based configuration instead of a `web.xml` file, we need to tell the WAR plugin not to fail when it can't find one.

**Java 17 compiler settings** — Spring 6 requires Java 17 as its minimum. The `maven.compiler.source` and `maven.compiler.target` properties ensure Maven compiles with Java 17.

```xml
<packaging>war</packaging>

<properties>
    <java.version>17</java.version>
    <spring.version>6.1.14</spring.version>
    <spring-security.version>6.2.7</spring-security.version>
</properties>
```

---

## Step 2: Create `AppInitializer.java` — The Application Entry Point

**What we're achieving:** Tell Tomcat how to start our Spring application — without writing any XML.

**File:** `src/main/java/com/example/AppInitializer.java`

### How it works

In the old days, you would write a `web.xml` file to register Spring's `DispatcherServlet`. Since Servlet 3.0, there's a better way: the **`WebApplicationInitializer`** interface. Tomcat discovers classes implementing this interface automatically via Java's `ServiceLoader` mechanism (specifically, through `SpringServletContainerInitializer` which is registered as a `ServletContainerInitializer`).

We extend `AbstractAnnotationConfigDispatcherServletInitializer`, which does the heavy lifting. We just override three methods:

```java
// Classes loaded into the ROOT application context (shared beans: security, services, data)
protected Class<?>[] getRootConfigClasses() {
    return new Class<?>[] { AppConfig.class, SecurityConfig.class };
}

// Classes loaded into the SERVLET application context (web-tier: controllers, view resolvers)
protected Class<?>[] getServletConfigClasses() {
    return new Class<?>[] { WebConfig.class };
}

// URL patterns the DispatcherServlet handles
protected String[] getServletMappings() {
    return new String[] { "/" };
}
```

### Why two separate contexts?

Spring MVC uses a **parent-child context** pattern:
- **Root context** (parent): Holds beans shared across the entire application — security configuration, services, data sources. Created first.
- **Servlet context** (child): Holds web-tier beans — controllers, view resolvers. Can see beans from the root context, but not vice versa.

This separation matters because Spring Security's filters operate at the **servlet container level** (before `DispatcherServlet`), so they must live in the root context, not the servlet context.

---

## Step 3: Create `AppConfig.java` — Root Application Context

**What we're achieving:** Enable component scanning so Spring can automatically discover our `@Controller`, `@Configuration`, and other annotated classes.

**File:** `src/main/java/com/example/config/AppConfig.java`

```java
@Configuration
@ComponentScan("com.example")
public class AppConfig {
}
```

- `@Configuration` — Marks this class as a source of Spring bean definitions.
- `@ComponentScan("com.example")` — Tells Spring to scan the `com.example` package (and sub-packages) for annotated classes (`@Controller`, `@Service`, `@Component`, etc.) and register them as beans.

In a larger application, this is where you'd define service beans, data sources, transaction managers, etc.

---

## Step 4: Create `WebConfig.java` — Spring MVC Configuration

**What we're achieving:** Set up Spring MVC's infrastructure and tell it how to find our JSP view files.

**File:** `src/main/java/com/example/config/WebConfig.java`

```java
@Configuration
@EnableWebMvc
public class WebConfig implements WebMvcConfigurer {

    @Bean
    public ViewResolver viewResolver() {
        InternalResourceViewResolver resolver = new InternalResourceViewResolver();
        resolver.setPrefix("/WEB-INF/views/");
        resolver.setSuffix(".jsp");
        return resolver;
    }
}
```

### Key pieces explained

**`@EnableWebMvc`** — This single annotation imports Spring MVC's entire default configuration: handler mappings (routing requests to controllers), message converters (JSON/XML serialization), argument resolvers, and more. Without it, `DispatcherServlet` has no infrastructure and cannot dispatch any requests.

**`InternalResourceViewResolver`** — When a controller method returns the string `"home"`, the view resolver translates it to the path `/WEB-INF/views/home.jsp`. The prefix and suffix are prepended and appended to the view name.

**Why `implements WebMvcConfigurer`?** — This interface lets you customize Spring MVC's defaults (add interceptors, configure CORS, register formatters, etc.). We don't override any methods here, but it's the standard pattern for MVC configuration classes.

---

## Step 5: Create `SecurityConfig.java` — Spring Security Configuration

**What we're achieving:** Define WHO can access the application and HOW they authenticate.

**File:** `src/main/java/com/example/config/SecurityConfig.java`

### The security filter chain

```java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        .authorizeHttpRequests(auth -> auth
            .requestMatchers("/login").permitAll()
            .anyRequest().authenticated()
        )
        .formLogin(form -> form
            .loginPage("/login")
            .defaultSuccessUrl("/", true)
        )
        .logout(logout -> logout
            .logoutSuccessUrl("/login?logout")
        );

    return http.build();
}
```

Line by line:
- **`.authorizeHttpRequests()`** — Defines authorization rules. `/login` is accessible to everyone (`permitAll()`); every other URL requires the user to be authenticated.
- **`.formLogin()`** — Enables form-based authentication. `.loginPage("/login")` tells Security to redirect unauthenticated users to our custom login page instead of the default one. `.defaultSuccessUrl("/", true)` sends users to `/` after successful login.
- **`.logout()`** — Enables the logout mechanism. Spring Security automatically handles `POST /logout`. After logout, the user is redirected to `/login?logout`.

### The user store

```java
@Bean
public UserDetailsService userDetailsService() {
    var user = User.withDefaultPasswordEncoder()
            .username("user")
            .password("password")
            .roles("USER")
            .build();

    return new InMemoryUserDetailsManager(user);
}
```

This creates a single in-memory user for testing. `withDefaultPasswordEncoder()` is **deprecated** — it's marked as such because it's not suitable for production (it uses a weak encoder and hardcoded credentials). For a tutorial, it's perfectly fine. In production, you would use `BCryptPasswordEncoder` with a database-backed `UserDetailsService`.

### CSRF protection

Spring Security 6 enables CSRF protection by default. This means every `POST` request must include a valid CSRF token. Our JSP forms include it as a hidden field (`${_csrf.parameterName}` / `${_csrf.token}`). If you forget this, form submissions will fail with a 403 Forbidden error.

---

## Step 6: Create `SecurityInitializer.java` — Register the Security Filter

**What we're achieving:** Wire Spring Security's filter chain into Tomcat's request processing pipeline.

**File:** `src/main/java/com/example/config/SecurityInitializer.java`

```java
public class SecurityInitializer extends AbstractSecurityWebApplicationInitializer {
    // Intentionally empty
}
```

**This class looks like dead code — but it's critical.** Its mere existence causes Spring Security's `DelegatingFilterProxy` (named `springSecurityFilterChain`) to be registered as a servlet filter with Tomcat. Every HTTP request passes through this filter before reaching `DispatcherServlet`.

Without this class:
- Your `SecurityConfig` bean exists in the Spring context
- But no servlet filter invokes it
- All your security rules are ignored
- Every page is accessible without authentication

**Do not delete this class**, even though it's empty.

---

## Step 7: Create `HomeController.java` — The HTTP Endpoints

**What we're achieving:** Define the two pages in our application — the secured home page and the login page.

**File:** `src/main/java/com/example/controller/HomeController.java`

```java
@Controller
public class HomeController {

    @GetMapping("/")
    public String home() {
        return "home";    // Resolves to /WEB-INF/views/home.jsp
    }

    @GetMapping("/login")
    public String login() {
        return "login";   // Resolves to /WEB-INF/views/login.jsp
    }
}
```

- **`@Controller`** (not `@RestController`) — Tells Spring this class handles HTTP requests and returns **view names**, not raw data. `@RestController` would write the return value directly to the response body.
- **`@GetMapping("/")`** — Maps `GET /` to the `home()` method. The returned string `"home"` is a view name that the `InternalResourceViewResolver` resolves to `/WEB-INF/views/home.jsp`.
- **`@GetMapping("/login")`** — Maps `GET /login` to our custom login page. This must match the `.loginPage("/login")` we configured in `SecurityConfig`.

---

## Step 8: Create the JSP Views

**What we're achieving:** Create the HTML pages the user actually sees — a login form and a secured home page.

### Why are JSPs inside `WEB-INF/`?

Files under `WEB-INF/` **cannot be accessed directly by URL**. A user cannot type `http://localhost:8080/minimal-spring/WEB-INF/views/home.jsp` in their browser — Tomcat blocks it. Every view request must go through a controller and the view resolver, which means it also passes through Spring Security's filter chain. This is a security best practice.

### `login.jsp`

**File:** `src/main/webapp/WEB-INF/views/login.jsp`

Key elements:
- **Form action** — `POST` to `${pageContext.request.contextPath}/login`. Spring Security's `UsernamePasswordAuthenticationFilter` intercepts `POST /login` automatically.
- **Field names** — `username` and `password`. These exact names are what Spring Security expects by default.
- **CSRF hidden field** — `<input type="hidden" name="${_csrf.parameterName}" value="${_csrf.token}" />`. Required because Spring Security rejects POST requests without a valid CSRF token.
- **Error/logout messages** — Conditional messages shown when `?error` or `?logout` query parameters are present.

### `home.jsp`

**File:** `src/main/webapp/WEB-INF/views/home.jsp`

Key elements:
- A welcome message confirming the user is logged in.
- A **logout form** that POSTs to `/logout` with a CSRF token. Spring Security handles the logout automatically.

---

## Step 9: Build the Application

**What we're achieving:** Compile the code, resolve dependencies, and package everything into a `.war` file.

```bash
mvn clean package
```

This command:
1. **`clean`** — Deletes the `target/` directory (any previous build artifacts)
2. **`package`** — Compiles Java source code, downloads dependencies, and assembles everything into `target/minimal-spring-1.0-SNAPSHOT.war`

If the build succeeds, you'll see:
```
[INFO] BUILD SUCCESS
[INFO] Building war: .../target/minimal-spring-1.0-SNAPSHOT.war
```

---

## Step 10: Deploy to Tomcat

**What we're achieving:** Get Tomcat to serve our application.

### Option A: Copy the WAR file

1. **Copy** `target/minimal-spring-1.0-SNAPSHOT.war` into Tomcat's `webapps/` directory
2. Optionally **rename** it to `minimal-spring.war` for a cleaner URL
3. **Start Tomcat** (run `bin/startup.sh` or `bin/startup.bat`)
4. Tomcat auto-extracts and deploys the WAR

### Option B: Use Tomcat Manager

If you have the Tomcat Manager app configured, you can deploy through its web interface at `http://localhost:8080/manager/html`.

### Context path

When deployed as `minimal-spring.war`, Tomcat serves the app under `/minimal-spring/`. All URLs become:
- `http://localhost:8080/minimal-spring/` — Home page
- `http://localhost:8080/minimal-spring/login` — Login page

If you rename the WAR to `ROOT.war`, it deploys at the root context path (`/`).

---

## Step 11: Verify It Works

1. **Open** `http://localhost:8080/minimal-spring/` in your browser
2. **Expect a redirect** to `http://localhost:8080/minimal-spring/login` — Spring Security blocks the unauthenticated request and redirects to the login page
3. **Log in** with username: `user`, password: `password`
4. **See the home page** with "Welcome! You are logged in."
5. **Click "Log Out"** — you're redirected back to the login page with a "You have been logged out." message
6. **Try accessing** `/` again — you're redirected to login, confirming the logout worked

---

## How It All Fits Together — The Request Flow

Here's what happens when a browser requests `http://localhost:8080/minimal-spring/`:

```
Browser
  │
  ▼
Tomcat (Servlet Container)
  │
  ▼
DelegatingFilterProxy ("springSecurityFilterChain")
  │  ← Registered by SecurityInitializer
  │  ← Configured by SecurityConfig
  │
  ├─ User NOT authenticated? → Redirect to /login
  │
  ├─ User IS authenticated? → Continue ▼
  │
  ▼
DispatcherServlet
  │  ← Registered by AppInitializer
  │  ← Configured by WebConfig
  │
  ▼
HomeController.home()
  │  ← Returns view name "home"
  │
  ▼
InternalResourceViewResolver
  │  ← Resolves "home" → /WEB-INF/views/home.jsp
  │
  ▼
home.jsp → HTML Response → Browser
```

---

## Common Pitfalls

### 1. Wrong Tomcat Version
**Symptom:** `ClassNotFoundException: jakarta.servlet.http.HttpServlet` or the app simply doesn't start.
**Cause:** Using Tomcat 9 (which uses `javax.servlet`) with Spring 6 (which requires `jakarta.servlet`).
**Fix:** Use Tomcat 10.1 or newer.

### 2. Missing CSRF Token in Forms
**Symptom:** 403 Forbidden when submitting the login form.
**Cause:** Spring Security rejects POST requests without a valid CSRF token.
**Fix:** Add `<input type="hidden" name="${_csrf.parameterName}" value="${_csrf.token}" />` to every form.

### 3. Deleted `SecurityInitializer.java`
**Symptom:** Security rules are ignored — all pages are accessible without login.
**Cause:** Without this class, the Spring Security filter chain is never registered with Tomcat.
**Fix:** Restore the class. It can be empty — its existence is what matters.

### 4. Application Loads at Wrong URL
**Symptom:** `http://localhost:8080/` shows 404, but `http://localhost:8080/minimal-spring/` works.
**Cause:** The WAR file name determines the context path. `minimal-spring.war` → `/minimal-spring/`.
**Fix:** Rename the WAR to `ROOT.war` to deploy at `/`, or adjust your URLs to include the context path.

### 5. JSPs Return as Plain Text
**Symptom:** Browser shows JSP source code instead of rendered HTML.
**Cause:** JSP engine not available or misconfigured.
**Fix:** Ensure Tomcat has the JSP engine (it does by default). Check that views are under `webapp/WEB-INF/views/` and the view resolver prefix/suffix match.
