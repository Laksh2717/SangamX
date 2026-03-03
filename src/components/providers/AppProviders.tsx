"use client";

import { CssBaseline, ThemeProvider } from "@mui/material";
import { PropsWithChildren } from "react";

import theme from "@/theme/theme";

export function AppProviders({ children }: PropsWithChildren) {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      {children}
    </ThemeProvider>
  );
}
