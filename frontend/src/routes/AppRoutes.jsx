import { Navigate, Route, Routes } from "react-router-dom";
import RegisterPage from "../pages/Register/RegisterPage";
import SuccessPage from "../pages/Success/SuccessPage";
import { PATHS } from "./paths";

export default function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to={PATHS.REGISTER} replace />} />
      <Route path={PATHS.REGISTER} element={<RegisterPage />} />
      <Route path={PATHS.SUCCESS} element={<SuccessPage />} />
    </Routes>
  );
}
