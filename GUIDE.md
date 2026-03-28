# Minimal Spring + Spring Security on Tomcat: A Step-by-Step Guide (web.xml edition)

This guide walks you through building a minimal **Spring Framework** (not Spring Boot) web application with **Spring Security**, deployed to **Apache Tomcat**. It uses the traditional **`web.xml`** approach that you'll encounter in most existing codebases. Every file is explained — what it does, why it exists, and how it connects to the rest.

## What Are We Building?

A web application with:
- A **secured home page** (`/`) that only logged-in users can see
- A **login page** (`/login`) with a username/password form
- **Spring Security** protecting all pages and handling authentication
- **WAR packaging** so Tomcat can deploy and run it
- **`web.xml`** as the central wiring file — the traditional way most Spring apps are configured

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
    │   ├── config/
    │   │   ├── AppConfig.java      ← Root application context
    │   │   ├── WebConfig.java      ← Spring MVC configuration
    │   │   └── SecurityConfig.java ← Spring Security rules
    │   └── controller/
    │       └── HomeController.java ← HTTP endpoints
    └── webapp/WEB-INF/
        ├── web.xml                 ← The central wiring file (THIS is the key file)
        └── views/
            ├── home.jsp            ← Secured home page
            └── login.jsp           ← Login form
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

## Step 2: Create `web.xml` — The Central Wiring File

**What we're achieving:** Tell Tomcat how to start Spring, where to find our configuration, and how to wire up Spring Security — all in one file.

**File:** `src/main/webapp/WEB-INF/web.xml`

This is **the most important file** in a traditional Spring application. It's the deployment descriptor that Tomcat reads when it deploys the WAR. Think of it as the "main()" of a web application — it tells the Servlet container what to create and in what order.

`web.xml` does three things for us:

### 2a. Create the Root Application Context (ContextLoaderListener)

```xml
<context-param>
    <param-name>contextClass</param-name>
    <param-value>org.springframework.web.context.support.AnnotationConfigWebApplicationContext</param-value>
</context-param>

<context-param>
    <param-name>contextConfigLocation</param-name>
    <param-value>com.example.config.AppConfig, com.example.config.SecurityConfig</param-value>
</context-param>

<listener>
    <listener-class>org.springframework.web.context.ContextLoaderListener</listener-class>
</listener>
```

**What this does:** When Tomcat starts, the `ContextLoaderListener` creates the **root Spring ApplicationContext**. This is the parent context that holds beans shared across the entire application — security configuration, services, data sources, etc.

**`contextClass`** — Tells Spring to use `AnnotationConfigWebApplicationContext`, meaning our configuration lives in Java `@Configuration` classes (not XML bean files). Without this parameter, Spring defaults to looking for an `applicationContext.xml` file.

**`contextConfigLocation`** — Lists the `@Configuration` classes to load into the root context: `AppConfig` (component scanning) and `SecurityConfig` (authentication/authorization rules).

**Why a listener?** A `ServletContextListener` runs code when the web application starts and stops. `ContextLoaderListener` uses this to create the Spring context on startup and destroy it on shutdown.

### 2b. Register the Spring Security Filter (DelegatingFilterProxy)

```xml
<filter>
    <filter-name>springSecurityFilterChain</filter-name>
    <filter-class>org.springframework.web.filter.DelegatingFilterProxy</filter-class>
</filter>

<filter-mapping>
    <filter-name>springSecurityFilterChain</filter-name>
    <url-pattern>/*</url-pattern>
</filter-mapping>
```

**What this does:** Registers Spring Security as a servlet filter that intercepts **every** HTTP request (`/*`) before it reaches the DispatcherServlet.

**`DelegatingFilterProxy`** — This is a bridge between the Servlet world and the Spring world. It's a standard servlet filter that delegates all its work to a Spring bean. The bean it delegates to has the same name as the `<filter-name>`: `springSecurityFilterChain`.

**Why `springSecurityFilterChain`?** — This exact name is critical. When you use `@EnableWebSecurity`, Spring Security automatically creates a bean called `springSecurityFilterChain` in the ApplicationContext. The `DelegatingFilterProxy` looks up this bean by name and forwards every request to it. If you change the `<filter-name>`, the lookup fails and security doesn't work.

**Why `/*` and not `/`?** — `/*` matches all requests including JSPs and static resources. `/` would only match requests handled by servlets, potentially letting some requests bypass security.

### 2c. Register the DispatcherServlet (Spring MVC Front Controller)

```xml
<servlet>
    <servlet-name>dispatcher</servlet-name>
    <servlet-class>org.springframework.web.servlet.DispatcherServlet</servlet-class>
    <init-param>
        <param-name>contextClass</param-name>
        <param-value>org.springframework.web.context.support.AnnotationConfigWebApplicationContext</param-value>
    </init-param>
    <init-param>
        <param-name>contextConfigLocation</param-name>
        <param-value>com.example.config.WebConfig</param-value>
    </init-param>
    <load-on-startup>1</load-on-startup>
</servlet>

<servlet-mapping>
    <servlet-name>dispatcher</servlet-name>
    <url-pattern>/</url-pattern>
</servlet-mapping>
```

**What this does:** Creates Spring MVC's `DispatcherServlet` and maps it to handle all requests at `/`.

**`DispatcherServlet`** — This is the front controller pattern. Every HTTP request comes to this single servlet, which then dispatches it to the appropriate `@Controller` method based on the URL mapping.

**Its own context** — The DispatcherServlet creates its **own** `ApplicationContext` (child of the root context). `contextConfigLocation` points to `WebConfig`, which holds web-tier beans: controllers, view resolvers, etc. This child context can see beans from the root context (security, services), but not vice versa.

**`load-on-startup=1`** — Tells Tomcat to create this servlet immediately on startup, not on the first request. This means Spring MVC initializes when Tomcat starts, so the first user request doesn't experience a slow startup.

### The order matters

When Tomcat reads `web.xml`, things happen in this order:
1. `<context-param>` values are read
2. `<listener>` — `ContextLoaderListener` creates the root Spring context (loads `AppConfig` + `SecurityConfig`)
3. `<filter>` — `DelegatingFilterProxy` is registered (it will look up `springSecurityFilterChain` from the root context)
4. `<servlet>` — `DispatcherServlet` creates its child context (loads `WebConfig`) because `load-on-startup=1`

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

This class is loaded by `ContextLoaderListener` because we listed it in `contextConfigLocation` in `web.xml`. In a larger application, this is where you'd define service beans, data sources, transaction managers, etc.

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

This class is loaded by the `DispatcherServlet` because we listed it in the servlet's `contextConfigLocation` in `web.xml`.

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

### How this connects to web.xml

This class is loaded into the **root context** by `ContextLoaderListener` (because we listed `SecurityConfig` in the root `contextConfigLocation`). The `@EnableWebSecurity` annotation causes Spring Security to create a bean named `springSecurityFilterChain`. The `DelegatingFilterProxy` declared in `web.xml` then finds this bean by name and delegates all filtering to it.

### CSRF protection

Spring Security 6 enables CSRF protection by default. This means every `POST` request must include a valid CSRF token. Our JSP forms include it as a hidden field (`${_csrf.parameterName}` / `${_csrf.token}`). If you forget this, form submissions will fail with a 403 Forbidden error.

---

## Step 6: Create `HomeController.java` — The HTTP Endpoints

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

## Step 7: Create the JSP Views

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

## Step 8: Build the Application

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

### What's inside the WAR?

```
minimal-spring-1.0-SNAPSHOT.war
├── WEB-INF/
│   ├── web.xml                          ← Tomcat reads this first
│   ├── classes/                         ← Your compiled .class files
│   │   └── com/example/...
│   ├── lib/                             ← All dependency JARs
│   │   ├── spring-webmvc-6.1.14.jar
│   │   ├── spring-security-web-6.2.7.jar
│   │   └── ...
│   └── views/
│       ├── home.jsp
│       └── login.jsp
├── META-INF/
│   └── MANIFEST.MF
```

---

## Step 9: Deploy to Tomcat

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

## Step 10: Verify It Works

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
Tomcat reads web.xml and sets up:
  │
  ▼
DelegatingFilterProxy ("springSecurityFilterChain")
  │  ← Declared in web.xml as a <filter>
  │  ← Delegates to the bean created by SecurityConfig
  │
  ├─ User NOT authenticated? → Redirect to /login
  │
  ├─ User IS authenticated? → Continue ▼
  │
  ▼
DispatcherServlet
  │  ← Declared in web.xml as a <servlet>
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

## How web.xml Connects Everything — The Big Picture

```
web.xml
  │
  ├── ContextLoaderListener
  │     └── Creates ROOT ApplicationContext
  │           ├── Loads AppConfig.java     → @ComponentScan
  │           └── Loads SecurityConfig.java → @EnableWebSecurity
  │                 └── Creates bean: "springSecurityFilterChain"
  │
  ├── DelegatingFilterProxy (filter-name: "springSecurityFilterChain")
  │     └── Looks up bean "springSecurityFilterChain" from root context
  │           └── Filters every request through Spring Security
  │
  └── DispatcherServlet
        └── Creates CHILD ApplicationContext
              └── Loads WebConfig.java → @EnableWebMvc + ViewResolver
                    └── Dispatches requests to @Controller methods
```

The key insight: **`web.xml` is the glue**. It tells Tomcat to create the Spring contexts, register the security filter, and set up the DispatcherServlet. The Java `@Configuration` classes define **what** the beans do; `web.xml` defines **when and where** they're loaded.

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

### 3. Wrong Filter Name in web.xml
**Symptom:** Security rules are ignored — all pages are accessible without login.
**Cause:** The `<filter-name>` is not `springSecurityFilterChain`, so `DelegatingFilterProxy` can't find the Spring Security bean.
**Fix:** The `<filter-name>` must be exactly `springSecurityFilterChain`.

### 4. Application Loads at Wrong URL
**Symptom:** `http://localhost:8080/` shows 404, but `http://localhost:8080/minimal-spring/` works.
**Cause:** The WAR file name determines the context path. `minimal-spring.war` → `/minimal-spring/`.
**Fix:** Rename the WAR to `ROOT.war` to deploy at `/`, or adjust your URLs to include the context path.

### 5. JSPs Return as Plain Text
**Symptom:** Browser shows JSP source code instead of rendered HTML.
**Cause:** JSP engine not available or misconfigured.
**Fix:** Ensure Tomcat has the JSP engine (it does by default). Check that views are under `webapp/WEB-INF/views/` and the view resolver prefix/suffix match.

### 6. Missing contextClass Parameter
**Symptom:** `FileNotFoundException: Could not open ServletContext resource [/WEB-INF/applicationContext.xml]`
**Cause:** Without the `contextClass` parameter, Spring defaults to XML-based configuration and looks for `applicationContext.xml`.
**Fix:** Add the `contextClass` parameter set to `AnnotationConfigWebApplicationContext` (as shown in our `web.xml`).

---

## web.xml vs. Java-Based Configuration — A Quick Comparison

You may see some projects that don't have a `web.xml` at all. They use Java classes instead:

| web.xml Approach (this guide) | Java Approach |
|-----|-----|
| `<listener>` + `ContextLoaderListener` | `AbstractAnnotationConfigDispatcherServletInitializer` |
| `<filter>` + `DelegatingFilterProxy` | `AbstractSecurityWebApplicationInitializer` |
| `<servlet>` + `DispatcherServlet` | `AbstractAnnotationConfigDispatcherServletInitializer` |

Both approaches do exactly the same thing — they register the same components with Tomcat. The `web.xml` approach is older and more widely used in existing codebases. The Java approach (Servlet 3.0+) is newer and avoids XML, but can be harder to understand because the wiring is hidden inside abstract base classes.

This guide uses `web.xml` because it makes the wiring **explicit and visible**. When you read `web.xml`, you can see at a glance: "there's a listener, a filter, and a servlet" — the three pillars of a Spring web application.
