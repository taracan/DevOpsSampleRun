import { Link, useLocation } from "react-router-dom";
import { PATHS } from "../../routes/paths";

export default function SuccessPage() {
  const name = useLocation().state?.name;

  return (
    <div className="card">
      <h1>Registered successfully!</h1>
      {name && <p>Welcome, {name}.</p>}
      <Link to={PATHS.REGISTER}>Register another user</Link>
    </div>
  );
}
