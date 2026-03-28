package com.example.config;

import org.springframework.security.web.context.AbstractSecurityWebApplicationInitializer;

public class SecurityInitializer extends AbstractSecurityWebApplicationInitializer {
    // This class can be empty.
    // Its existence triggers registration of the Spring Security filter chain
    // (DelegatingFilterProxy) with the Servlet container.
}
