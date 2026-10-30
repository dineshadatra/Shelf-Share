import { Route, Routes } from "react-router-dom";
import { ProtectedRoute } from "@/components/auth/protected-route";
import HomePage from "@/pages/home-page";
import DiscoverPage from "@/pages/discover-page";
import BookDetailsPage from "@/pages/book-details-page";
import LoginPage from "@/pages/login-page";
import RegisterPage from "@/pages/register-page";
import VerificationPage from "@/pages/verification-page";
import ReaderDashboardPage from "@/pages/reader-dashboard-page";
import OwnerDashboardPage from "@/pages/owner-dashboard-page";
import ListBookPage from "@/pages/list-book-page";
import WishlistPage from "@/pages/wishlist-page";
import RentalHistoryPage from "@/pages/rental-history-page";
import CommunityPage from "@/pages/community-page";
import ChatPage from "@/pages/chat-page";
import NotificationsPage from "@/pages/notifications-page";
import ProfilePage from "@/pages/profile-page";
import AdminLoginPage from "@/pages/admin-login-page";
import AdminDashboardPage from "@/pages/admin-dashboard-page";
import AdminVerificationQueuePage from "@/pages/admin-verification-queue-page";
import NotFoundPage from "@/pages/not-found-page";

export default function App() {
  return <Routes>
    <Route path="/" element={<HomePage />} />
    <Route path="/discover" element={<DiscoverPage />} />
    <Route path="/books/:id" element={<BookDetailsPage />} />
    <Route path="/login" element={<LoginPage />} />
    <Route path="/register" element={<RegisterPage />} />
    <Route path="/admin/login" element={<AdminLoginPage />} />
    <Route path="/reader" element={<ProtectedRoute><ReaderDashboardPage /></ProtectedRoute>} />
    <Route path="/owner" element={<ProtectedRoute><OwnerDashboardPage /></ProtectedRoute>} />
    <Route path="/owner/list-book" element={<ProtectedRoute><ListBookPage /></ProtectedRoute>} />
    <Route path="/wishlist" element={<ProtectedRoute><WishlistPage /></ProtectedRoute>} />
    <Route path="/rentals" element={<ProtectedRoute><RentalHistoryPage /></ProtectedRoute>} />
    <Route path="/community" element={<ProtectedRoute><CommunityPage /></ProtectedRoute>} />
    <Route path="/chat" element={<ProtectedRoute><ChatPage /></ProtectedRoute>} />
    <Route path="/notifications" element={<ProtectedRoute><NotificationsPage /></ProtectedRoute>} />
    <Route path="/profile" element={<ProtectedRoute><ProfilePage /></ProtectedRoute>} />
    <Route path="/verification" element={<ProtectedRoute><VerificationPage /></ProtectedRoute>} />
    <Route path="/admin" element={<ProtectedRoute staffOnly><AdminDashboardPage /></ProtectedRoute>} />
    <Route path="/admin/verifications" element={<ProtectedRoute staffOnly><AdminVerificationQueuePage /></ProtectedRoute>} />
    <Route path="*" element={<NotFoundPage />} />
  </Routes>;
}
