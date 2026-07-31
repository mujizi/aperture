import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";
import { CompanionApp } from "./CompanionApp";
import "./styles.css";

const surface = new URLSearchParams(window.location.search).get("surface");
if (surface) document.documentElement.dataset.surface = surface;

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    {surface === "companion" ? <CompanionApp /> : <App />}
  </React.StrictMode>
);
