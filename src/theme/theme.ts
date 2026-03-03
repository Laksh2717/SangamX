import { createTheme } from "@mui/material/styles";

const theme = createTheme({
  palette: {
    mode: "light",
    primary: {
      main: "#4f46e5",
    },
    secondary: {
      main: "#0f766e",
    },
  },
  shape: {
    borderRadius: 10,
  },
});

export default theme;
